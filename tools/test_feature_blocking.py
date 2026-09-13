import unittest
from feature_blocking import blocking_flag, feature_blocking


def placement(x, z, width, height, blocking):
    return dict(x=x, z=z, width=width, height=height, blocking=blocking)


class FeatureBlockingTests(unittest.TestCase):
    def test_flag_defaults_to_zero_and_uses_low_bit(self):
        self.assertEqual(blocking_flag({}), 0)
        self.assertEqual([blocking_flag({'blocking': value}) for value in ['0', '1', '2', '3']], [0, 1, 0, 1])

    def test_nonblocking_feature_leaves_cells_open(self):
        self.assertEqual(feature_blocking(4, 4, [placement(1, 1, 2, 2, False)]), bytes(16))

    def test_multi_cell_footprint_covers_anchor_and_continuations(self):
        grid = feature_blocking(6, 5, [placement(1, 2, 3, 2, True)])
        cells = {(i % 6, i // 6) for i, value in enumerate(grid) if value}
        self.assertEqual(cells, {(x, z) for x in range(1, 4) for z in range(2, 4)})

    def test_zero_sized_footprint_still_blocks_anchor(self):
        self.assertEqual(feature_blocking(3, 3, [placement(2, 1, 0, 0, True)])[1 * 3 + 2], 1)

    def test_rejects_out_of_bounds_footprint(self):
        with self.assertRaises(ValueError):
            feature_blocking(4, 4, [placement(3, 3, 2, 1, True)])


if __name__ == '__main__':
    unittest.main()
