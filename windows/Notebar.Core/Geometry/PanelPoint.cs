namespace Notebar.Core.Geometry;

/// <summary>A point in device-independent pixels.</summary>
/// <remarks>
/// Windows screen coordinates are top-left origin with Y increasing downward.
/// Nothing in the core depends on that — see <see cref="Notebar.Core.Panel.EdgeZone"/>
/// for why every expression is written against a rect's min and max instead.
/// </remarks>
public readonly record struct PanelPoint(double X, double Y);
