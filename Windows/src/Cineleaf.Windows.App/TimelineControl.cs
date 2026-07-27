using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Cineleaf.Core;

namespace Cineleaf.Windows;

public sealed class ClipSelectedEventArgs(Guid? clipId) : EventArgs
{
    public Guid? ClipId { get; } = clipId;
}

public sealed class ClipMoveRequestedEventArgs(Guid clipId, RationalTime start) : EventArgs
{
    public Guid ClipId { get; } = clipId;
    public RationalTime Start { get; } = start;
}

public sealed class AssetDroppedEventArgs(Guid assetId, Guid trackId, RationalTime start) : EventArgs
{
    public Guid AssetId { get; } = assetId;
    public Guid TrackId { get; } = trackId;
    public RationalTime Start { get; } = start;
}

public sealed class TimelineControl : FrameworkElement
{
    private const double HeaderWidth = 82;
    private const double RulerHeight = 25;
    private const double TrackHeight = 48;
    private CineleafProject? _project;
    private TimelineIndex? _index;
    private double _pixelsPerSecond = 72;
    private double _scrollSeconds;
    private Guid? _selectedClipId;
    private Guid? _dragClipId;
    private Point _mouseDown;
    private double _dragOffsetSeconds;
    private RationalTime? _dragTime;

    public TimelineControl()
    {
        Focusable = true;
        AllowDrop = true;
        ClipToBounds = true;
    }

    public event EventHandler<ClipSelectedEventArgs>? ClipSelected;
    public event EventHandler<ClipMoveRequestedEventArgs>? ClipMoveRequested;
    public event EventHandler<AssetDroppedEventArgs>? AssetDropped;

    public RationalTime Playhead { get; set; } = RationalTime.Zero;

    public void SetProject(CineleafProject project, Guid? selectedClipId)
    {
        _project = project;
        _index = new TimelineIndex(project.Timeline);
        _selectedClipId = selectedClipId;
        InvalidateVisual();
    }

    public void Zoom(double factor, double? anchorSeconds = null)
    {
        var old = _pixelsPerSecond;
        _pixelsPerSecond = Math.Clamp(_pixelsPerSecond * factor, 16, 480);
        if (anchorSeconds is { } anchor)
            _scrollSeconds = Math.Max(0, anchor - (anchor - _scrollSeconds) * old / _pixelsPerSecond);
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        drawingContext.DrawRectangle(new SolidColorBrush(Color.FromRgb(14, 22, 18)), null, new Rect(RenderSize));
        if (_project is null || _index is null) return;
        DrawRuler(drawingContext);
        var visibleDuration = Math.Max(1, (ActualWidth - HeaderWidth) / _pixelsPerSecond);
        var visible = new RationalTimeRange(RationalTime.FromSeconds(_scrollSeconds), RationalTime.FromSeconds(visibleDuration));
        var typeface = new Typeface("Segoe UI");
        for (var trackIndex = 0; trackIndex < _project.Timeline.Tracks.Count; trackIndex++)
        {
            var track = _project.Timeline.Tracks[trackIndex];
            var y = RulerHeight + trackIndex * TrackHeight;
            var row = new Rect(0, y, ActualWidth, TrackHeight - 1);
            drawingContext.DrawRectangle(new SolidColorBrush(trackIndex % 2 == 0 ? Color.FromRgb(24, 34, 29) : Color.FromRgb(21, 30, 26)), null, row);
            DrawText(drawingContext, track.Name, typeface, 12, Brushes.White, new Point(10, y + 15));
            var state = track.IsLocked ? "🔒" : track.IsMuted ? "M" : string.Empty;
            if (state.Length > 0) DrawText(drawingContext, state, typeface, 10, Brushes.LightGray, new Point(59, y + 16));
            foreach (var clip in _index.Visible(track.Id, visible)) DrawClip(drawingContext, clip, y, typeface);
        }
        foreach (var marker in _project.Timeline.Markers.Where(marker => marker.Time.Seconds >= _scrollSeconds && marker.Time.Seconds <= _scrollSeconds + visibleDuration))
        {
            var x = TimeToX(marker.Time.Seconds);
            drawingContext.DrawLine(new Pen(Brushes.Gold, 1), new Point(x, RulerHeight), new Point(x, ActualHeight));
        }
        var playheadX = TimeToX(Playhead.Seconds);
        if (playheadX >= HeaderWidth && playheadX <= ActualWidth)
        {
            drawingContext.DrawLine(new Pen(new SolidColorBrush(Color.FromRgb(103, 211, 145)), 2),
                new Point(playheadX, 0), new Point(playheadX, ActualHeight));
        }
        if (_dragTime is { } dragTime)
        {
            var x = TimeToX(dragTime.Seconds);
            drawingContext.DrawLine(new Pen(Brushes.White, 1), new Point(x, RulerHeight), new Point(x, ActualHeight));
        }
    }

    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        if ((Keyboard.Modifiers & ModifierKeys.Control) != 0)
        {
            var anchor = XToTime(e.GetPosition(this).X);
            Zoom(e.Delta > 0 ? 1.2 : 1 / 1.2, anchor);
        }
        else
        {
            _scrollSeconds = Math.Max(0, _scrollSeconds - e.Delta / 120d * Math.Max(0.5, 120 / _pixelsPerSecond));
            InvalidateVisual();
        }
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        Focus();
        _mouseDown = e.GetPosition(this);
        var hit = HitClip(_mouseDown);
        _selectedClipId = hit?.Clip.Id;
        ClipSelected?.Invoke(this, new ClipSelectedEventArgs(_selectedClipId));
        if (hit is not null)
        {
            _dragClipId = hit.Value.Clip.Id;
            _dragOffsetSeconds = XToTime(_mouseDown.X) - hit.Value.Clip.TimelineStart.Seconds;
            CaptureMouse();
        }
        else if (_mouseDown.X >= HeaderWidth)
        {
            Playhead = RationalTime.FromSeconds(Math.Max(0, XToTime(_mouseDown.X)));
        }
        InvalidateVisual();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (_dragClipId is null || e.LeftButton != MouseButtonState.Pressed || Math.Abs(e.GetPosition(this).X - _mouseDown.X) < 3) return;
        _dragTime = Snap(Math.Max(0, XToTime(e.GetPosition(this).X) - _dragOffsetSeconds));
        InvalidateVisual();
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        if (_dragClipId is { } clipId && _dragTime is { } start)
            ClipMoveRequested?.Invoke(this, new ClipMoveRequestedEventArgs(clipId, start));
        _dragClipId = null;
        _dragTime = null;
        ReleaseMouseCapture();
        InvalidateVisual();
    }

    protected override void OnDrop(DragEventArgs e)
    {
        base.OnDrop(e);
        if (_project is null || !e.Data.GetDataPresent("CineleafAsset") || e.Data.GetData("CineleafAsset") is not string value || !Guid.TryParse(value, out var assetId)) return;
        var point = e.GetPosition(this);
        var trackIndex = (int)((point.Y - RulerHeight) / TrackHeight);
        if (trackIndex < 0 || trackIndex >= _project.Timeline.Tracks.Count) return;
        AssetDropped?.Invoke(this, new AssetDroppedEventArgs(assetId, _project.Timeline.Tracks[trackIndex].Id,
            Snap(Math.Max(0, XToTime(point.X)))));
    }

    protected override void OnDragOver(DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent("CineleafAsset") ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void DrawRuler(DrawingContext context)
    {
        context.DrawRectangle(new SolidColorBrush(Color.FromRgb(18, 27, 23)), null, new Rect(0, 0, ActualWidth, RulerHeight));
        var typeface = new Typeface("Segoe UI");
        var step = _pixelsPerSecond switch { >= 240 => 1d, >= 80 => 2d, >= 32 => 5d, _ => 10d };
        var first = Math.Floor(_scrollSeconds / step) * step;
        for (var second = first; TimeToX(second) <= ActualWidth; second += step)
        {
            var x = TimeToX(second);
            if (x < HeaderWidth) continue;
            context.DrawLine(new Pen(new SolidColorBrush(Color.FromRgb(70, 85, 77)), 1), new Point(x, 17), new Point(x, RulerHeight));
            DrawText(context, FormatTime(second), typeface, 10, Brushes.LightGray, new Point(x + 3, 3));
        }
    }

    private void DrawClip(DrawingContext context, TimelineClip clip, double y, Typeface typeface)
    {
        var start = TimeToX(clip.TimelineStart.Seconds);
        var end = TimeToX(clip.TimelineEnd.Seconds);
        var rect = new Rect(Math.Max(HeaderWidth, start), y + 5, Math.Max(2, Math.Min(ActualWidth, end) - Math.Max(HeaderWidth, start)), TrackHeight - 11);
        var color = clip.Kind switch
        {
            ClipKind.Audio => Color.FromRgb(54, 125, 97),
            ClipKind.Text => Color.FromRgb(128, 91, 174),
            ClipKind.Image => Color.FromRgb(60, 120, 160),
            _ => Color.FromRgb(45, 106, 80)
        };
        var fill = new SolidColorBrush(color);
        var border = clip.Id == _selectedClipId ? new Pen(Brushes.White, 2) : new Pen(new SolidColorBrush(Color.FromRgb(100, 170, 135)), 1);
        context.DrawRoundedRectangle(fill, border, rect, 4, 4);
        if (rect.Width > 24) DrawText(context, clip.Name, typeface, 11, Brushes.White, new Point(rect.X + 7, rect.Y + 8), Math.Max(0, rect.Width - 12));
    }

    private (TimelineTrack Track, TimelineClip Clip)? HitClip(Point point)
    {
        if (_project is null || point.X < HeaderWidth || point.Y < RulerHeight) return null;
        var trackIndex = (int)((point.Y - RulerHeight) / TrackHeight);
        if (trackIndex < 0 || trackIndex >= _project.Timeline.Tracks.Count) return null;
        var track = _project.Timeline.Tracks[trackIndex];
        var time = RationalTime.FromSeconds(XToTime(point.X));
        var clip = track.Clips.FirstOrDefault(item => time >= item.TimelineStart && time < item.TimelineEnd);
        return clip is null ? null : (track, clip);
    }

    private RationalTime Snap(double seconds)
    {
        if (_project is null) return RationalTime.FromSeconds(seconds);
        var frames = _project.FrameRate switch { ProjectFrameRate.Fps24 => 24, ProjectFrameRate.Fps25 => 25, ProjectFrameRate.Fps50 => 50, ProjectFrameRate.Fps60 => 60, _ => 30 };
        return RationalTime.FromSeconds(Math.Round(seconds * frames) / frames, 60_000);
    }

    private double TimeToX(double seconds) => HeaderWidth + (seconds - _scrollSeconds) * _pixelsPerSecond;
    private double XToTime(double x) => _scrollSeconds + (x - HeaderWidth) / _pixelsPerSecond;
    private static string FormatTime(double seconds) => TimeSpan.FromSeconds(Math.Max(0, seconds)).ToString(seconds >= 3600 ? @"h\:mm\:ss" : @"m\:ss", CultureInfo.InvariantCulture);

    private static void DrawText(DrawingContext context, string text, Typeface typeface, double size, Brush brush, Point origin, double width = double.PositiveInfinity)
    {
        var formatted = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, typeface, size, brush, 1)
        { Trimming = TextTrimming.CharacterEllipsis };
        if (double.IsFinite(width)) formatted.MaxTextWidth = Math.Max(1, width);
        context.DrawText(formatted, origin);
    }
}
