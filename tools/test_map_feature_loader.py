import unittest
from map_feature_loader import load, blocking, schema_features, msvc_atoi, NONE, CONTINUATION, VOID, POOL
from prepare_maps import select_schema


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

    def test_schema_entries_parse_like_atoi(self):
        schema = {'features': {'feature0': {'featurename': 'Rock', 'xpos': ' +12abc', 'zpos': '7.9'},
                               'feature1': {'featurename': 'Tree', 'xpos': '-1', 'zpos': '3'},
                               'feature2': {'xpos': '1', 'zpos': '1'},
                               'feature3': {'featurename': 'Tree', 'zpos': '2'}}}
        self.assertEqual(schema_features(schema), [('Rock', 12, 7), ('', -1, 3), ('', 1, 1), ('', -1, 2)])
        self.assertEqual((msvc_atoi('4294967297'), msvc_atoi('-5x'), msvc_atoi('x5')), (1, -5, 0))

    def test_schema_features_centre_3d_and_append_definitions(self):
        definitions = [dict(feature(3, 3), name='rock'), dict(feature(1, 1, has_object=False), name='tree')]
        extra = {'crate': dict(feature(2, 2), name='crate')}
        grid = load(8, 8, [NONE] * 64, definitions, [('ROCK', 4, 4), ('Tree', 0, 7), ('crate', 7, 7), ('Crate', 0, 0), ('', 1, 1)], extra)
        self.assertEqual(grid.codes[3 * 8 + 3], 0)
        self.assertEqual(grid.codes[7 * 8], 1)
        self.assertEqual(grid.codes[6 * 8 + 6], 2)  # a 2x2 crate at xpos 7 centres to (6, 6) and fits the 8-cell map
        self.assertEqual([definition['name'] for definition in grid.definitions], ['rock', 'tree', 'crate'])
        self.assertEqual(grid.skipped_schema_features, [('Crate', -1, -1)])

    def test_schema_selection_follows_start_position_counts(self):
        def schema(kind, starts, tag):
            return dict(type=kind, tag=tag, specials={f'special{i}': dict(specialwhat=f'StartPos{i + 1}') for i in range(starts)})
        # Painted Desert shape: StartPos counts 10, 2, 4 in Network schemas.
        descriptor = {'schema 0': schema('Network 1', 10, 'a'), 'schema 1': schema('network 1', 2, 'b'), 'schema 2': schema('Network 1', 4, 'c')}
        self.assertEqual(select_schema(descriptor, 2)['tag'], 'b')
        self.assertEqual(select_schema(descriptor, 3)['tag'], 'a')
        self.assertEqual(select_schema(descriptor, 0)['tag'], 'c')
        # Best persists across types; a missing index ends the walk; non-network and empty schemas are ignored.
        descriptor = {'schema 0': schema('Easy', 6, 'x'), 'schema 1': schema('Network 2', 6, 'y'), 'schema 2': schema('Network 1', 0, 'z'), 'schema 4': schema('Network 1', 8, 'w')}
        self.assertEqual(select_schema(descriptor, 2)['tag'], 'y')
        self.assertIsNone(select_schema({'schema 0': schema('Easy', 2, 'e')}, 2))

    def test_blocking_predicate(self):
        attributes = [NONE] * 16
        attributes[0], attributes[10], attributes[15] = 0, 1, VOID
        grid = load(4, 4, attributes, [feature(2, 2), feature(1, 1)])
        self.assertEqual(list(blocking(grid, [True, False])), [1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])


if __name__ == '__main__':
    unittest.main()
