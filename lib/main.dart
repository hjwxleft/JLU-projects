import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() {
  runApp(const BleControlApp());
}

class BleControlApp extends StatelessWidget {
  const BleControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static final preferredServiceUuid =
      Uuid.parse('BCE9EBFB-BFEE-03A1-B7D7-E587C728441E');
  static final preferredTxUuid =
      Uuid.parse('5E400002-B5A3-F393-E0A9-E50E24DCCA9E');
  static final preferredRxUuid =
      Uuid.parse('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');
  static const permissionChannel = MethodChannel('ble_ui/permissions');

  static const Preset offPreset = Preset(
    code: '00',
    label: 'ON/OFF',
    display: '0.0 Hz',
    mode: ModeState.off,
  );
  static const Preset dcPreset = Preset(
    code: '28',
    label: 'Direct Current',
    display: 'DC',
    mode: ModeState.direct,
  );
  static const List<Preset> frequencyPresets = <Preset>[
    Preset(
        code: '20',
        label: '0.5Hz',
        display: '0.5 Hz',
        mode: ModeState.alternate),
    Preset(
        code: '21', label: '1Hz', display: '1.0 Hz', mode: ModeState.alternate),
    Preset(
        code: '22', label: '2Hz', display: '2.0 Hz', mode: ModeState.alternate),
    Preset(
        code: '23', label: '5Hz', display: '5.0 Hz', mode: ModeState.alternate),
    Preset(
        code: '24', label: '8Hz', display: '8.0 Hz', mode: ModeState.alternate),
    Preset(
        code: '25',
        label: '10Hz',
        display: '10.0 Hz',
        mode: ModeState.alternate),
    Preset(
        code: '26',
        label: '16Hz',
        display: '16.0 Hz',
        mode: ModeState.alternate),
    Preset(
        code: '27',
        label: '20Hz',
        display: '20.0 Hz',
        mode: ModeState.alternate),
  ];

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, DiscoveredDevice> _scanResults =
      <String, DiscoveredDevice>{};
  final List<CharOption> _allChars = <CharOption>[];
  final List<String> _logs = <String>[];

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  DiscoveredDevice? _device;
  CharOption? _txOption;
  CharOption? _rxOption;
  QualifiedCharacteristic? _txChar;
  QualifiedCharacteristic? _rxChar;
  bool _txWithResponse = false;

  bool _connected = false;
  bool _connecting = false;
  bool _scanning = false;

  String _displayValue = '0.0 Hz';
  ModeState _mode = ModeState.off;

  bool get _canSend => _connected && _txChar != null;

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    super.dispose();
  }

  void _log(String group, String message) {
    if (!mounted) return;
    final line = '$group: $message';
    setState(() {
      _logs.insert(0, line);
      if (_logs.length > 80) _logs.removeLast();
    });
  }

  T? _firstWhereOrNull<T>(Iterable<T> source, bool Function(T item) test) {
    for (final item in source) {
      if (test(item)) return item;
    }
    return null;
  }

  Future<bool> _ensureScanPermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await permissionChannel.invokeMapMethod<String, dynamic>(
        'requestBlePermissions',
      );
      final granted = result?['granted'] == true;
      final locationEnabled = result?['locationEnabled'] == true;
      if (!granted) {
        _log('ERR', 'BLE and location permissions are required.');
        return false;
      }
      if (!locationEnabled) {
        _log('ERR', 'Location service must be enabled before BLE scan.');
        return false;
      }
      return true;
    } catch (e) {
      _log('ERR', 'Permission check failed: $e');
      return false;
    }
  }

  Future<void> _onBluetoothTap() async {
    if (_connecting || _scanning) return;
    if (!await _ensureScanPermissions()) return;

    _scanResults.clear();
    _scanning = true;
    setState(() {});
    _log('SYS', 'Start scanning nearby BLE devices.');

    Object? scanError;
    await _scanSub?.cancel();
    _scanSub = _ble.scanForDevices(withServices: []).listen(
      (device) {
        final isNew = !_scanResults.containsKey(device.id);
        _scanResults[device.id] = device;
        if (isNew) {
          final name = device.name.trim().isEmpty
              ? 'Unnamed Device'
              : device.name.trim();
          _log('SYS', 'Found: $name (${device.id})');
        }
      },
      onError: (e) => scanError = e,
    );
    await Future<void>.delayed(const Duration(seconds: 6));
    await _scanSub?.cancel();
    _scanSub = null;

    _scanning = false;
    setState(() {});

    if (scanError != null) {
      _log('ERR', 'Scan failed: $scanError');
      return;
    }

    final devices = _scanResults.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    _log('SYS', 'Scan complete: ${devices.length} device(s).');

    final selected = await _pickDevice(devices);
    if (selected == null) {
      _log('SYS', 'Selection canceled.');
      return;
    }
    _device = selected;
    final name =
        selected.name.trim().isEmpty ? 'Unnamed Device' : selected.name.trim();
    _log('SYS', 'Selected: $name (${selected.id})');
    await _connectToDevice(selected);
  }

  Future<DiscoveredDevice?> _pickDevice(List<DiscoveredDevice> devices) async {
    if (!mounted || devices.isEmpty) return null;
    return showModalBottomSheet<DiscoveredDevice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            itemCount: devices.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              if (index == 0) {
                return const ListTile(
                  title: Text('Select BLE Device'),
                  subtitle: Text('Manual selection from scan results'),
                );
              }
              final d = devices[index - 1];
              final name =
                  d.name.trim().isEmpty ? 'Unnamed Device' : d.name.trim();
              return ListTile(
                title: Text(name),
                subtitle: Text(d.id),
                trailing: Text('${d.rssi} dBm'),
                onTap: () => Navigator.of(ctx).pop(d),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _connectToDevice(DiscoveredDevice device) async {
    _connecting = true;
    _connected = false;
    await _notifySub?.cancel();
    await _connSub?.cancel();
    setState(() {});

    _connSub = _ble.connectToDevice(id: device.id).listen(
      (update) {
        switch (update.connectionState) {
          case DeviceConnectionState.connected:
            unawaited(_onConnected(device.id));
            break;
          case DeviceConnectionState.disconnected:
            _onDisconnected('Connection disconnected.');
            break;
          case DeviceConnectionState.connecting:
            _connecting = true;
            if (mounted) setState(() {});
            break;
          case DeviceConnectionState.disconnecting:
            _connecting = false;
            if (mounted) setState(() {});
            break;
        }
      },
      onError: (e) {
        _connecting = false;
        _connected = false;
        _log('ERR', 'Connection failed: $e');
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _onConnected(String deviceId) async {
    _connecting = false;
    _connected = true;
    _log('SYS', 'Connected: $deviceId');
    if (mounted) setState(() {});
    await _discoverAndAutoBind(deviceId);
  }

  void _onDisconnected(String message) {
    _connecting = false;
    _connected = false;
    _txOption = null;
    _rxOption = null;
    _txChar = null;
    _rxChar = null;
    _notifySub?.cancel();
    _log('SYS', message);
    if (mounted) setState(() {});
  }

  Future<void> _discoverAndAutoBind(String deviceId) async {
    _allChars.clear();
    _txOption = null;
    _rxOption = null;
    _txChar = null;
    _rxChar = null;
    _txWithResponse = false;
    await _notifySub?.cancel();

    try {
      await _ble.discoverAllServices(deviceId);
      final services = await _ble.getDiscoveredServices(deviceId);
      _log('SYS', 'Discovered ${services.length} service(s).');
      _log('SYS', 'Service UUID list: ${services.map((s) => s.id).join(', ')}');

      for (final service in services) {
        for (final c in service.characteristics) {
          _allChars.add(
            CharOption(
              serviceId: service.id,
              charId: c.id,
              writeNoRsp: c.isWritableWithoutResponse,
              writeRsp: c.isWritableWithResponse,
              notify: c.isNotifiable,
              indicate: c.isIndicatable,
            ),
          );
        }
      }

      final preferredTx = _firstWhereOrNull(
        _allChars,
        (o) =>
            o.serviceId == preferredServiceUuid &&
            o.charId == preferredTxUuid &&
            o.canTx,
      );
      final preferredRx = _firstWhereOrNull(
        _allChars,
        (o) =>
            o.serviceId == preferredServiceUuid &&
            o.charId == preferredRxUuid &&
            o.canRx,
      );

      _txOption = preferredTx ??
          _firstWhereOrNull(_allChars, (o) => o.writeNoRsp) ??
          _firstWhereOrNull(_allChars, (o) => o.writeRsp);
      _rxOption = preferredRx ??
          _firstWhereOrNull(_allChars, (o) => o.notify) ??
          _firstWhereOrNull(_allChars, (o) => o.indicate);

      if (_txOption != null) {
        _bindTx(deviceId, _txOption!);
        _log('SYS', 'Auto TX: ${_txOption!.charId}');
      } else {
        _log('ERR', 'Auto TX not found.');
      }
      if (_rxOption != null) {
        _bindRx(deviceId, _rxOption!);
        _log('SYS', 'Auto RX: ${_rxOption!.charId}');
        await _startNotify();
      } else {
        _log('ERR', 'Auto RX not found.');
      }
    } catch (e) {
      _log('ERR', 'Service discovery failed: $e');
    }

    if (mounted) setState(() {});
  }

  void _bindTx(String deviceId, CharOption option) {
    _txOption = option;
    _txChar = QualifiedCharacteristic(
      serviceId: option.serviceId,
      characteristicId: option.charId,
      deviceId: deviceId,
    );
    _txWithResponse = !option.writeNoRsp && option.writeRsp;
  }

  void _bindRx(String deviceId, CharOption option) {
    _rxOption = option;
    _rxChar = QualifiedCharacteristic(
      serviceId: option.serviceId,
      characteristicId: option.charId,
      deviceId: deviceId,
    );
  }

  Future<void> _startNotify() async {
    final rx = _rxChar;
    if (rx == null) return;
    await _notifySub?.cancel();
    _notifySub = _ble.subscribeToCharacteristic(rx).listen(
      (data) {
        final decoded = utf8.decode(data, allowMalformed: true).trim();
        final hex =
            data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        _log('RX', '$hex | $decoded');
        if (RegExp(r'^\d{2}$').hasMatch(decoded)) {
          _applyCodeToUi(decoded);
        }
        if (mounted) setState(() {});
      },
      onError: (e) {
        _log('ERR', 'Notification failed: $e');
        if (mounted) setState(() {});
      },
    );
  }

  bool _applyCodeToUi(String code) {
    Preset? preset;
    if (code == offPreset.code) {
      preset = offPreset;
    } else if (code == dcPreset.code) {
      preset = dcPreset;
    } else {
      preset = _firstWhereOrNull(frequencyPresets, (p) => p.code == code);
    }
    if (preset == null) return false;
    _displayValue = preset.display;
    _mode = preset.mode;
    return true;
  }

  Future<void> _sendPreset(Preset preset) async {
    if (!_connected) {
      _log('SYS', 'Device is not connected.');
      return;
    }
    if (_txChar == null) {
      _log('SYS', 'Please configure TX characteristic first.');
      return;
    }
    try {
      final payload = utf8.encode(preset.code);
      if (_txWithResponse) {
        await _ble.writeCharacteristicWithResponse(_txChar!, value: payload);
      } else {
        await _ble.writeCharacteristicWithoutResponse(_txChar!, value: payload);
      }
      _applyCodeToUi(preset.code);
      _log('TX', '${preset.code} (${preset.label})');
      if (mounted) setState(() {});
    } catch (e) {
      _log('ERR', 'Write failed: $e');
    }
  }

  Future<void> _onCodeTap() async {
    if (!_connected || _device == null) {
      _showSnack('Connect a device first.');
      return;
    }
    if (_allChars.isEmpty) {
      _showSnack('No discovered characteristics yet.');
      return;
    }

    final txCandidates = _allChars.where((c) => c.canTx).toList();
    final rxCandidates = _allChars.where((c) => c.canRx).toList();
    CharOption? selectedTx = _txOption;
    CharOption? selectedRx = _rxOption;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Characteristic Settings',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Discovered ${_allChars.length} characteristic(s)',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      const Text('TX (Writable)',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      if (txCandidates.isEmpty)
                        const Text('No writable characteristic found.')
                      else
                        ...txCandidates.map(
                          (c) => RadioListTile<CharOption>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: c,
                            groupValue: selectedTx,
                            onChanged: (v) =>
                                setSheetState(() => selectedTx = v),
                            title: Text(c.shortLabel),
                            subtitle: Text(c.capabilityLabel),
                          ),
                        ),
                      const SizedBox(height: 10),
                      const Text('RX (Notify/Indicate)',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      RadioListTile<CharOption?>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: null,
                        groupValue: selectedRx,
                        onChanged: (v) => setSheetState(() => selectedRx = v),
                        title: const Text('None'),
                        subtitle:
                            const Text('Do not subscribe to notification'),
                      ),
                      ...rxCandidates.map(
                        (c) => RadioListTile<CharOption?>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: c,
                          groupValue: selectedRx,
                          onChanged: (v) => setSheetState(() => selectedRx = v),
                          title: Text(c.shortLabel),
                          subtitle: Text(c.capabilityLabel),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: selectedTx == null
                                  ? null
                                  : () async {
                                      await _applyManualChars(
                                          selectedTx!, selectedRx);
                                      if (!ctx.mounted) return;
                                      Navigator.of(ctx).pop();
                                    },
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applyManualChars(CharOption tx, CharOption? rx) async {
    final device = _device;
    if (device == null) return;
    await _notifySub?.cancel();

    _bindTx(device.id, tx);
    _log('SYS', 'Manual TX: ${tx.charId}');

    if (rx != null) {
      _bindRx(device.id, rx);
      _log('SYS', 'Manual RX: ${rx.charId}');
      await _startNotify();
    } else {
      _rxOption = null;
      _rxChar = null;
    }
    if (mounted) setState(() {});
  }

  void _showSnack(String text) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = _device == null
        ? 'No Device'
        : (_device!.name.trim().isEmpty
            ? 'Unnamed Device'
            : _device!.name.trim());
    final leftPillText = _connected ? 'Connected' : 'Disconnected';
    final leftPillColor =
        _connected ? const Color(0xFF16A34A) : const Color(0xFFEF4444);
    final progressText =
        _scanning ? 'Scanning...' : (_connecting ? 'Connecting...' : null);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF3FB),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FBFF), Color(0xFFEAF0FA)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              children: [
                Panel(
                  child: Column(
                    children: [
                      StatusPill(text: leftPillText, color: leftPillColor),
                      if (progressText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          progressText,
                          style: const TextStyle(
                            color: Color(0xFFD97706),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        _displayValue,
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deviceName,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ModePill(
                        label: 'Alternate Current',
                        active: _mode == ModeState.alternate,
                      ),
                      const SizedBox(height: 4),
                      ModePill(
                        label: 'Direct Current',
                        active: _mode == ModeState.direct,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Panel(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          RoundAction(
                            icon: Icons.bluetooth_rounded,
                            label: 'Bluetooth',
                            onTap: _onBluetoothTap,
                          ),
                          const SizedBox(width: 28),
                          RoundAction(
                            icon: Icons.tune_rounded,
                            label: 'Code',
                            onTap: _onCodeTap,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, _) {
                    return Panel(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Voltage Regulation',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: frequencyPresets.length + 1,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 1.8,
                                  ),
                                  itemBuilder: (_, index) {
                                    final p = index < frequencyPresets.length
                                        ? frequencyPresets[index]
                                        : offPreset;
                                    return CommandButton(
                                      label: p.label,
                                      enabled: _canSend,
                                      onTap: () => _sendPreset(p),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            height: 1,
                            color: const Color(0xFFE2E8F0),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap:
                                  _canSend ? () => _sendPreset(dcPreset) : null,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(10, 10, 10, 10),
                                child: Ink(
                                  width: double.infinity,
                                  height: 82,
                                  decoration: BoxDecoration(
                                    color: _mode == ModeState.direct
                                        ? const Color(0xFFF4F7FF)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFFCBD5E1),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Direct Current',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w400,
                                          color: Color(0xFF64748B),
                                          fontFamily: 'sans-serif-rounded',
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (!_canSend) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Send is disabled. Configure TX characteristic first.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum ModeState { off, alternate, direct, unknown }

class Preset {
  const Preset({
    required this.code,
    required this.label,
    required this.display,
    required this.mode,
  });

  final String code;
  final String label;
  final String display;
  final ModeState mode;
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class ModePill extends StatelessWidget {
  const ModePill({
    super.key,
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final foreground =
        active ? const Color(0xFF1F9D55) : const Color(0xFF94A3B8);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: active ? foreground.withOpacity(0.12) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              active ? foreground.withOpacity(0.28) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: foreground,
        ),
      ),
    );
  }
}

class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFEFF), Color(0xFFE7EEF8)],
              ),
              border: Border.all(color: const Color(0xFFD7DFEE)),
            ),
            child: Icon(icon, size: 34, color: const Color(0xFF1E3A8A)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class CommandButton extends StatelessWidget {
  const CommandButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: enabled ? onTap : null,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF0F172A),
        disabledBackgroundColor: const Color(0xFFF1F5F9),
        disabledForegroundColor: const Color(0xFF94A3B8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class CharOption {
  const CharOption({
    required this.serviceId,
    required this.charId,
    required this.writeNoRsp,
    required this.writeRsp,
    required this.notify,
    required this.indicate,
  });

  final Uuid serviceId;
  final Uuid charId;
  final bool writeNoRsp;
  final bool writeRsp;
  final bool notify;
  final bool indicate;

  bool get canTx => writeNoRsp || writeRsp;
  bool get canRx => notify || indicate;

  String get shortLabel =>
      '${serviceId.toString().substring(0, 8)} / ${charId.toString().substring(0, 8)}';

  String get capabilityLabel {
    final caps = <String>[];
    if (writeNoRsp) caps.add('WriteNoRsp');
    if (writeRsp) caps.add('WriteRsp');
    if (notify) caps.add('Notify');
    if (indicate) caps.add('Indicate');
    return 'Service: $serviceId\nChar: $charId\n${caps.join(' | ')}';
  }
}
