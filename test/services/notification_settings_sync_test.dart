import 'package:beecount/services/system/notification_settings_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('snapshot 未設定時回傳預設值', () async {
    final s = await NotificationSettingsSync.snapshot();
    expect(s['reminder_enabled'], false);
    expect(s['reminder_hour'], 21);
    expect(s['cc_due_reminder_maxdays'], 3);
    expect(s.length, 10);
  });

  test('applyFromServer 只寫有差異且型別正確的 key,並回報是否變動', () async {
    final changed = await NotificationSettingsSync.applyFromServer({
      'reminder_enabled': true,
      'reminder_hour': 8,
      'reminder_minute': 'bad', // 型別錯誤,忽略
      'cc_reminder_days': 5,
      'cc_reminder_hour': 10, // 與預設相同,不算變動
    });
    expect(changed, true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('reminder_enabled'), true);
    expect(prefs.getInt('reminder_hour'), 8);
    expect(prefs.containsKey('reminder_minute'), false);
    expect(prefs.getInt('cc_reminder_days'), 5);
    expect(prefs.containsKey('cc_reminder_hour'), false);

    expect(
      await NotificationSettingsSync.applyFromServer({'reminder_hour': 8}),
      false,
    );
  });

  test('notifyChanged 在未指派時為 no-op,指派後會觸發', () {
    NotificationSettingsSync.onChanged = null;
    NotificationSettingsSync.notifyChanged();
    var n = 0;
    NotificationSettingsSync.onChanged = () => n++;
    NotificationSettingsSync.notifyChanged();
    expect(n, 1);
    NotificationSettingsSync.onChanged = null;
  });
}
