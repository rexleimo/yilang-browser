import 'package:flutter/material.dart';

import '../../../core/logic/board_model.dart';
import '../../../core/widgets/home_background_picker.dart';
import '../../../theme/app_theme.dart';

/// 首页「浏览器设置」底部弹层。
void showHomeSettingsSheet(BuildContext context, BoardModel m) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('浏览器设置',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                const Text('首页背景',
                    style:
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                const SizedBox(height: 10),
                HomeBackgroundPicker(model: m),
                const SizedBox(height: 12),
                HomeSettingRow(
                  label: '搜索引擎',
                  trailing: TextButton(
                    onPressed: () {
                      m.settings.searchEngineIndex =
                          (m.settings.searchEngineIndex + 1) %
                              Settings.engines.length;
                      m.save();
                      setSheet(() {});
                    },
                    child: Text(
                        '${Settings.engines[m.settings.searchEngineIndex]} ›',
                        style: const TextStyle(color: AppColors.subText)),
                  ),
                ),
                HomeSettingRow(
                  label: '广告拦截',
                  trailing: HomeSwitchRow(
                    value: m.settings.adBlock,
                    onChanged: (v) {
                      m.settings.adBlock = v;
                      m.save();
                      setSheet(() {});
                    },
                  ),
                ),
                HomeSettingRow(
                  label: '无痕浏览',
                  trailing: HomeSwitchRow(
                    value: m.settings.incognito,
                    onChanged: (v) {
                      m.settings.incognito = v;
                      m.save();
                      setSheet(() {});
                    },
                  ),
                ),
                HomeSettingRow(
                  label: '书签云同步',
                  trailing: HomeSwitchRow(
                    value: m.settings.sync,
                    onChanged: (v) {
                      m.settings.sync = v;
                      m.save();
                      setSheet(() {});
                    },
                  ),
                ),
                const HomeSettingRow(
                    label: '关于一览 Yilan',
                    trailing: Text('v0.1',
                        style: TextStyle(color: AppColors.subText))),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFF0F2F7)),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HomeSettingRow extends StatelessWidget {
  const HomeSettingRow({super.key, required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13.5, color: AppColors.ink)),
          trailing,
        ],
      ),
    );
  }
}

class HomeSwitchRow extends StatelessWidget {
  const HomeSwitchRow({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      activeThumbColor: AppColors.success,
      onChanged: onChanged,
    );
  }
}
