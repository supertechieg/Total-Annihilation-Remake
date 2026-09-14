import unittest
from map_feature_loader import load, blocking, NONE, CONTINUATION, VOID, POOL


def feature(fx=1, fz=1, indestructible=False, has_object=True):
    return dict(footprintx=fx & 0xffff, footprintz=fz & 0xffff, indestructible=indestructible, object=has_object)


class MapFeatureLoaderTests(unittest.TestCase):
    def test_later_placement_removes_overlapped_destructible_feature(self):
        attributes = [NONE] * 16
        attributes[0] = 0
        attributes[5] = 1
        grid = load(4, 4, attributes, [feature(2, 2), feature(2, 2)])
        self.assertEqual(grid.codes[0], NONE)
        self.assertEqual(grid.codes[5], 1)
        self.assertEqual([grid.codes[i] for i in (1, 4)], [NONE, NONE])
        self.assertEqual([grid.codes[i] for i in (6, 9, 10)], [CONTINUATION] * 3)

    def test_indestructible_feature_blocks_later_overlap(self):
        attributes = [NONE] * 16
        attributes[0], attributes[1] = 0, 1
        grid = load(4, 4, attributes, [feature(2, 2, indestructible=True), feature(1, 1)])
        self.assertEqual(grid.codes[0], 0)
        self.assertEqual(grid.codes[1], CONTINUATION)

    def test_void_cells_are_written_first_and_refuse_features(self):
        attributes = [NONE] * 16
        attributes[0], attributes[1] = 0, VOID
        grid = load(4, 4, attributes, [feature(2, 1)])
        self.assertEqual(grid.codes[:2], [NONE, VOID])

    def test_failed_placement_keeps_earlier_removals(self):
        attributes = [NONE] * 16
        attributes[1], attributes[2], attributes[4] = 0, 1, 2
        grid = load(4, 4, attributes, [feature(1, 2), feature(1, 2, indestructible=True), feature(3, 1)])
        # C at cell 4 removes A through its continuation at cell 5, then fails on B's continuation at cell 6.
        self.assertEqual([grid.codes[i] for i in (1, 5)], [NONE, NONE])
        self.assertEqual([grid.codes[i] for i in (2, 6)], [1, CONTINUATION])
        self.assertEqual(grid.codes[4], NONE)

    def test_edge_and_zero_footprints(self):
        attributes = [NONE] * 16
        attributes[3], attributes[6] = 0, 1
        grid = load(4, 4, attributes, [feature(2, 1), feature(0, 0)])
        self.assertEqual(grid.codes[3], NONE)
        self.assertEqual(grid.codes[6], 1)

    def test_codes_beyond_the_feature_count_are_ignored(self):
        grid = load(2, 2, [1, 0xfffe, 0xfffd, 0], [feature()])
        self.assertEqual(grid.codes, [NONE, NONE, NONE, 0])

    def test_instance_pool_exhaustion(self):
        grid = load(64, 64, [0] * 3000 + [NONE] * (64 * 64 - 3000), [feature()])
        self.assertEqual(sum(1 for code in grid.codes if code == 0), POOL)
        grid = load(64, 64, [0] * 3000 + [NONE] * (64 * 64 - 3000), [feature(has_object=False)])
        self.assertEqual(sum(1 for code in grid.codes if code == 0), 3000)

    def test_blocking_predicate(self):
        attributes = [NONE] * 16
        attributes[0], attributes[10], attributes[15] = 0, 1, VOID
        grid = load(4, 4, attributes, [feature(2, 2), feature(1, 1)])
        self.assertEqual(list(blocking(grid, [True, False])), [1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])


if __name__ == '__main__':
    unittest.main()
