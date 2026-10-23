import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/settings_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/provider.dart';
import '../../state/assets_controller.dart';
import '../../state/settings_controller.dart';

class TopicGatePage extends StatefulWidget {
  const TopicGatePage({super.key});

  @override
  State<TopicGatePage> createState() => _TopicGatePageState();
}

class _TopicGatePageState extends State<TopicGatePage> {
  int _tab = 0;
  bool _hasSystemOneKey = false;
  bool _systemOneObscure = true;
  String _systemTwoProvider = 'deepseek';
  bool _hasSystemTwoKey = false;
  bool _systemTwoObscure = true;
  final TextEditingController _systemOneKey = TextEditingController();
  final TextEditingController _systemTwoKey = TextEditingController();
  double _threshold = 0.5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadSystemOne();
      _reloadSystemTwo();
    });
  }

  @override
  void dispose() {
    _systemOneKey.dispose();
    _systemTwoKey.dispose();
    super.dispose();
  }

  Future<void> _reloadSystemOne() async {
    final SettingsController settings = context.read<SettingsController>();
    final String key = await settings.readSystemOneKey();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasSystemOneKey = key.trim().isNotEmpty;
      _threshold = settings.topicGateThreshold;
    });
  }

  Future<void> _reloadSystemTwo() async {
    final SettingsController settings = context.read<SettingsController>();
    final String key = await settings.readProviderKey(_systemTwoProvider);
    if (!mounted) {
      return;
    }
    setState(() => _hasSystemTwoKey = key.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final SettingsController settings = context.watch<SettingsController>();
    final SettingsStrings s = SettingsStrings(settings.language);
    return Scaffold(
      backgroundColor: c.pageBg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(context, s),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.borderSoft),
                    ),
                    child: SwitchListTile(
                      value: settings.topicGateEnabled,
                      onChanged: (bool value) => _toggleEnabled(value, s),
                      title: Text(
                        s.t('settings_topic_gate'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        s.t('settings_topic_gate_desc'),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: c.textMuted,
                        ),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      _TabChip(
                        label: s.t('settings_system_one'),
                        selected: _tab == 0,
                        onTap: () => setState(() => _tab = 0),
                      ),
                      const SizedBox(width: 8),
                      _TabChip(
                        label: s.t('settings_system_two'),
                        selected: _tab == 1,
                        onTap: () => setState(() => _tab = 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_tab == 0)
                    _buildSystemOne(context, settings, s)
                  else
                    _buildSystemTwo(context, settings, s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SettingsStrings s) {
    final AppColors c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(21),
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(21),
              ),
              child: Text(
                '‹',
                style: TextStyle(
                  fontSize: 28,
                  height: 1,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.t('settings_topic_gate_title'),
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: c.textTitle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemOne(
    BuildContext context,
    SettingsController settings,
    SettingsStrings s,
  ) {
    final AppColors c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InfoCard(
          title: s.t('settings_system_one'),
          description: s.t('settings_system_one_desc'),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                s.t('settings_channel'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  _TabChip(
                    label: s.t('settings_channel_typesafe'),
                    selected: settings.topicGateChannel == 'typesafe',
                    onTap: () => _selectChannel('typesafe'),
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: 'OpenRouter',
                    selected: settings.topicGateChannel == 'openrouter',
                    onTap: () => _selectChannel('openrouter'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Text(
                    s.t('settings_topic_gate_key'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _hasSystemOneKey
                        ? s.t('settings_key_configured')
                        : s.t('settings_key_missing'),
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          _hasSystemOneKey ? c.statusGood : c.dangerText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _systemOneKey,
                obscureText: _systemOneObscure,
                decoration: InputDecoration(
                  hintText: _hasSystemOneKey
                      ? s.t('settings_topic_gate_key_saved')
                      : s.t('settings_topic_gate_key_placeholder'),
                  suffixIcon: TextButton(
                    onPressed: () => setState(
                      () => _systemOneObscure = !_systemOneObscure,
                    ),
                    child: Text(
                      _systemOneObscure ? '显示' : '隐藏',
                      style: TextStyle(fontSize: 12, color: c.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () => _saveSystemOneKey(s),
                        child: Text(s.t('settings_topic_gate_save')),
                      ),
                    ),
                  ),
                  if (_hasSystemOneKey) ...<Widget>[
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.dangerText,
                          ),
                          onPressed: () => _clearSystemOneKey(s),
                          child: Text(s.t('settings_topic_gate_clear_key')),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Text(
                    s.t('settings_topic_gate_threshold'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _threshold.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 13,
                      color: c.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _threshold.clamp(0.1, 0.9),
                min: 0.1,
                max: 0.9,
                divisions: 8,
                onChanged: (double value) =>
                    setState(() => _threshold = value),
                onChangeEnd: settings.setTopicGateThreshold,
              ),
              Text(
                s.t('settings_topic_gate_threshold_hint'),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: c.textFaint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSystemTwo(
    BuildContext context,
    SettingsController settings,
    SettingsStrings s,
  ) {
    final AppColors c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InfoCard(
          title: s.t('settings_system_two'),
          description: s.t('settings_system_two_desc'),
          footnote: s.t('settings_system_two_shared'),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                s.t('settings_provider'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: providers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final ProviderDefinition p = providers[index];
                    return _TabChip(
                      label: p.name,
                      selected: p.id == _systemTwoProvider,
                      onTap: () {
                        setState(() {
                          _systemTwoProvider = p.id;
                          _systemTwoKey.clear();
                        });
                        _reloadSystemTwo();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Text(
                    'Key',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _hasSystemTwoKey
                        ? s.t('settings_key_configured')
                        : s.t('settings_key_missing'),
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          _hasSystemTwoKey ? c.statusGood : c.dangerText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _systemTwoKey,
                obscureText: _systemTwoObscure,
                decoration: InputDecoration(
                  hintText: _hasSystemTwoKey
                      ? s.t('settings_topic_gate_key_saved')
                      : 'Paste API Key',
                  suffixIcon: TextButton(
                    onPressed: () => setState(
                      () => _systemTwoObscure = !_systemTwoObscure,
                    ),
                    child: Text(
                      _systemTwoObscure ? '显示' : '隐藏',
                      style: TextStyle(fontSize: 12, color: c.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () => _saveSystemTwoKey(),
                        child: Text(s.t('settings_topic_gate_save')),
                      ),
                    ),
                  ),
                  if (_hasSystemTwoKey) ...<Widget>[
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.dangerText,
                          ),
                          onPressed: () => _clearSystemTwoKey(),
                          child: Text(s.t('settings_topic_gate_clear_key')),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _toggleEnabled(bool value, SettingsStrings s) async {
    final SettingsController settings = context.read<SettingsController>();
    if (value) {
      final String key = await settings.readSystemOneKey();
      if (key.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('settings_topic_gate_need_key'))),
          );
        }
        return;
      }
    }
    await settings.setTopicGateEnabled(value);
  }

  Future<void> _selectChannel(String channel) async {
    final SettingsController settings = context.read<SettingsController>();
    await settings.setTopicGateChannel(channel);
    _systemOneKey.clear();
    await _reloadSystemOne();
  }

  Future<void> _saveSystemOneKey(SettingsStrings s) async {
    final SettingsController settings = context.read<SettingsController>();
    final String text = _systemOneKey.text.trim();
    if (text.isEmpty) {
      if (!_hasSystemOneKey && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('settings_topic_gate_need_key'))),
        );
      }
      return;
    }
    await settings.writeSystemOneKey(text);
    _systemOneKey.clear();
    setState(() => _hasSystemOneKey = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存 Jev Key')),
      );
    }
  }

  Future<void> _clearSystemOneKey(SettingsStrings s) async {
    final SettingsController settings = context.read<SettingsController>();
    await settings.deleteSystemOneKey();
    await settings.setTopicGateEnabled(false);
    if (mounted) {
      setState(() => _hasSystemOneKey = false);
    }
  }

  Future<void> _saveSystemTwoKey() async {
    final SettingsController settings = context.read<SettingsController>();
    final AssetsController assets = context.read<AssetsController>();
    final String text = _systemTwoKey.text.trim();
    if (text.isEmpty) {
      return;
    }
    await settings.writeProviderKey(_systemTwoProvider, text);
    await assets.reloadKeys();
    _systemTwoKey.clear();
    if (mounted) {
      setState(() => _hasSystemTwoKey = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存服务商 Key')),
      );
    }
  }

  Future<void> _clearSystemTwoKey() async {
    final SettingsController settings = context.read<SettingsController>();
    final AssetsController assets = context.read<AssetsController>();
    await settings.deleteProviderKey(_systemTwoProvider);
    await assets.reloadKeys();
    if (mounted) {
      setState(() => _hasSystemTwoKey = false);
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.borderSoft),
      ),
      child: child,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.description,
    this.footnote,
  });

  final String title;
  final String description;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.accentOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          if (footnote != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              footnote!,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: c.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.accentSolid : c.fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? c.accentContrast : c.textPrimary,
          ),
        ),
      ),
    );
  }
}
