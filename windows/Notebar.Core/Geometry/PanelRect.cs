namespace Notebar.Core.Geometry;

/// <summary>A rectangle in device-independent pixels. <paramref name="Y"/> is the
/// top edge, matching Windows screen coordinates.</summary>
public readonly record struct PanelRect(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MaxX => X + Width;
    public double MinY => Y;
    public double MaxY => Y + Height;
    public double MidX => X + Width / 2;
    public double MidY => Y + Height / 2;

    public bool Contains(PanelPoint p) =>
        p.X >= MinX && p.X <= MaxX && p.Y >= MinY && p.Y <= MaxY;

    /// <summary>Grows the rect by <paramref name="dx"/> on each horizontal edge and
    /// <paramref name="dy"/> on each vertical edge. Negative values shrink it.</summary>
    public PanelRect Inflate(double dx, double dy) =>
        new(X - dx, Y - dy, Width + 2 * dx, Height + 2 * dy);
}
