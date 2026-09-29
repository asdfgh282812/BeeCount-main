import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _E = ({String? syncId, String name});

List<String?> _pick(
  List<_E> local, {
  Set<String> remoteSyncIds = const {},
  Set<String> remoteKeys = const {},
  Set<String> pendingSyncIds = const {},
}) =>
    selectBackfillCandidates<_E>(
      local: local,
      syncIdOf: (e) => e.syncId,
      keyOf: (e) => e.name,
      remoteSyncIds: remoteSyncIds,
      remoteKeys: remoteKeys,
      pendingSyncIds: pendingSyncIds,
    ).map((e) => e.syncId).toList();

void main() {
  test('server 已有同 syncId 的实体不补写(2026-09-29 覆盖事故)', () {
    expect(
      _pick([(syncId: 'a', name: '国泰CUBE卡')], remoteSyncIds: {'a'}),
      isEmpty,
    );
  });

  test('server 已有同名的实体不补写,比对忽略前后空白', () {
    expect(
      _pick([(syncId: 'b', name: ' 餐饮 ')], remoteKeys: {'餐饮'}),
      isEmpty,
    );
  });

  test('没有 syncId 或已有待推送 change 的跳过', () {
    expect(
      _pick(
        [
          (syncId: null, name: 'x'),
          (syncId: '', name: 'y'),
          (syncId: 'p', name: 'z')
        ],
        pendingSyncIds: {'p'},
      ),
      isEmpty,
    );
  });

  test('server 上完全没有的本机实体才补写', () {
    expect(
      _pick(
        [(syncId: 'a', name: 'A'), (syncId: 'new', name: '新标签')],
        remoteSyncIds: {'a'},
        remoteKeys: {'A'},
      ),
      ['new'],
    );
  });
}
