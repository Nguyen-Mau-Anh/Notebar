using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SortOrderTests
{
    [Fact]
    public void BetweenTwoNeighboursIsStrictlyBetween()
    {
        double mid = SortOrder.Between(1.0, 2.0);
        Assert.True(mid > 1.0 && mid < 2.0);
    }

    [Fact]
    public void MovingToTheFrontIsBelowTheFirst() =>
        Assert.True(SortOrder.Between(null, 5.0) < 5.0);

    [Fact]
    public void MovingToTheEndIsAboveTheLast() =>
        Assert.True(SortOrder.Between(5.0, null) > 5.0);

    [Fact]
    public void AnEmptyListStartsAtZero() =>
        Assert.Equal(0.0, SortOrder.Between(null, null));

    /// Repeatedly inserting at the same spot halves the gap each time. Doubles
    /// run out of room after roughly 50 such inserts, and the result is two rows
    /// with an identical sort order and a list whose order flickers. Assert the
    /// depth the arithmetic actually survives, so anyone who later needs more
    /// knows they must renumber rather than discovering it from a bug report.
    [Fact]
    public void SurvivesFiftyRepeatedInsertsAtTheSameSpot()
    {
        double low = 0.0, high = 1.0;
        for (int i = 0; i < 50; i++)
        {
            double mid = SortOrder.Between(low, high);
            Assert.True(mid > low && mid < high, $"collapsed after {i} inserts");
            high = mid;
        }
    }
}
