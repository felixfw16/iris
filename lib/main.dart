import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'domain.dart';
import 'native_bridge.dart';
import 'rupiah.dart';

class CameraPreview extends StatelessWidget {
  const CameraPreview({super.key});
  static const viewType = 'id.sahabatnetra/camera';
  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const ExcludeSemantics(child: AndroidView(viewType: viewType));
      case TargetPlatform.iOS:
        return const ExcludeSemantics(child: UiKitView(viewType: viewType));
      default:
        return const ColoredBox(
            color: Color(0xff172930),
            child: Center(
                child: Text('Pratinjau kamera tidak tersedia pada platform ini.',
                    textAlign: TextAlign.center)));
    }
  }
}

void main() => runApp(const NetraApp());

class NetraApp extends StatelessWidget {
  const NetraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IRIS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff80efce),
              brightness: Brightness.dark,
              primary: const Color(0xff80efce),
              surface: const Color(0xff111d23)),
          scaffoldBackgroundColor: const Color(0xff091318),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 58),
                  textStyle: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 56))),
          textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(minimumSize: const Size(64, 48))),
          iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _native = NativeBridge();
  final _gate = NarrationGate();
  StreamSubscription<Map<Object?, Object?>>? _subscription;
  Map<Object?, Object?> _status = {};
  ScanMode _mode = ScanMode.objects;
  String _message = 'Selamat datang. Pilih mode, lalu arahkan kamera.';
  String _lastNarration = '';
  bool _scanning = false, _busy = false, _listening = false, _online = false;
  bool _qwenThinking = false;
  bool _cameraAllowed = false;
  bool _announceMessage = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _native.updates.listen(_onEvent,
        onError: (Object _) => _show('Layanan perangkat belum tersedia.'));
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final status = await _native.status();
      if (mounted)
        setState(() {
          _status = status;
          _cameraAllowed = status['cameraPermission'] == true;
        });
    } on PlatformException catch (error) {
      _show(error.message ?? 'Tidak dapat membaca status perangkat.');
    } on MissingPluginException {
      _show('Jalankan aplikasi di Android untuk memakai kamera dan AI.');
    }
  }

  Widget _gated(Widget child) => MergeSemantics(
      child: Semantics(
          hint: !_busy && !_listening
              ? null
              : _listening
                  ? 'Belum dapat dipakai, mikrofon sedang merekam'
                  : 'Belum dapat dipakai, permintaan sebelumnya masih diproses',
          child: child));

  void _show(String text, {bool announce = true}) {
    if (mounted) {
      setState(() {
        _message = text;
        _announceMessage = announce;
      });
    }
  }

  Future<void> _say(String text) async {
    _show(text, announce: false);
    _lastNarration = text;
    try {
      await _native.speak(text);
    } on PlatformException catch (_) {
      if (_message == text) _show(text);
    }
  }

  void _onEvent(Map<Object?, Object?> event) {
    if (!mounted) return;
    if (event['type'] == 'ready') {
      unawaited(_refresh());
      return;
    }
    if (event['type'] == 'status') {
      if (event['generation'] != null && event['generation'] != _generation)
        return;
      _show(event['message'] as String? ?? '');
      return;
    }
    if (event['type'] == 'error') {
      unawaited(_say(event['message'] as String? ?? 'Pemrosesan gagal.'));
      return;
    }
    if (event['type'] == 'objects' &&
        _scanning &&
        !_busy &&
        !_listening &&
        event['generation'] == _generation) {
      final items = (event['items'] as List? ?? [])
          .map((item) =>
              Observation.fromMap(Map<Object?, Object?>.from(item as Map)))
          .toList();
      final text = narrateObjects(items);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_gate.accept(text, (event['capturedAt'] as num?)?.toInt() ?? 0, now))
        unawaited(_say(text));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_stop());
    }
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<bool> _ensureCamera() async {
    final allowed = await _native.call<bool>('requestCamera') ?? false;
    if (mounted) setState(() => _cameraAllowed = allowed);
    if (!allowed)
      await _say(
          'Izin kamera diperlukan. Aktifkan melalui pengaturan aplikasi.');
    return allowed;
  }

  Future<void> _stop() async {
    _generation++;
    if (mounted)
      setState(() {
        _scanning = false;
        _listening = false;
        _busy = false;
      });
    try {
      await _native.call<void>('stop', {'generation': _generation});
    } on PlatformException catch (_) {}
  }

  Future<void> _select(ScanMode mode) async {
    await _stop();
    if (!mounted) return;
    setState(() => _mode = mode);
    await _say(switch (mode) {
      ScanMode.objects =>
        'Mode objek. Tekan Mulai pindai untuk mengenali lingkungan.',
      ScanMode.text =>
        'Mode tulisan. Arahkan kamera ke tulisan lalu tekan Baca tulisan.',
      ScanMode.family =>
        'Mode keluarga. Arahkan kamera ke wajah lalu tekan Kenali wajah.',
    });
  }

  Future<void> _run(Future<String?> Function() task) async {
    if (_busy || _listening) return;
    await _stop();
    final generation = _generation;
    if (mounted) setState(() => _busy = true);
    try {
      if (!await _ensureCamera()) return;
      final text = await task();
      if (mounted && generation == _generation && text != null)
        await _say(text);
    } on PlatformException catch (error) {
      if (mounted && generation == _generation)
        await _say(error.message ?? 'Pemrosesan gagal. Silakan coba lagi.');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _primary() async {
    if (_scanning) {
      await _stop();
      return;
    }
    if (_mode == ScanMode.objects) {
      try {
        if (!await _ensureCamera()) return;
        _gate.reset();
        await _native.call<void>('startScan', {'generation': ++_generation});
        if (mounted)
          setState(() {
            _scanning = true;
            _message = 'Pemindaian aktif. Gerakkan kamera perlahan.';
          });
      } on PlatformException catch (error) {
        await _say(error.message ?? 'Kamera belum siap.');
      }
    } else {
      await _run(() => _native.call<String>(
          _mode == ScanMode.text ? 'readText' : 'recognizeFamily'));
    }
  }

  Future<void> _distance() => _run(() async {
        final response = await _native.call<Map>('measureDistance');
        final items = (response?['items'] as List? ?? [])
            .map((item) =>
                Observation.fromMap(Map<Object?, Object?>.from(item as Map)))
            .toList();
        return narrateObjects(items, withDistance: true);
      });

  Future<void> _rupiah() => _run(() async {
        _show('Arahkan satu lembar rupiah ke kamera. Membaca tulisan nominal…');
        return narrateRupiah(await _native.call<String>('readText') ?? '');
      });

  Future<void> _describe() async {
    if (!_online) {
      await _say(
          'Mode di perangkat aktif. Aktifkan mode online di pengaturan untuk mengirim foto ke layanan online.');
      return;
    }
    await _run(
        () => _native.call<String>('describePhoto', {'online': _online}));
  }

  Future<void> _listen() async {
    if (_busy || _listening) return;
    await _stop();
    try {
      if (await _native.call<bool>('requestMicrophone') != true) {
        await _say('Izin mikrofon diperlukan untuk perintah suara.');
        return;
      }
    } on PlatformException catch (error) {
      await _say(error.message ?? 'Mikrofon belum tersedia.');
      return;
    }
    final generation = _generation;
    if (mounted)
      setState(() {
        _listening = true;
        _message = 'Menyiapkan mikrofon dan model suara…';
      });
    try {
      final text = await _native.call<String>('listen') ?? '';
      if (!mounted || generation != _generation) return;
      setState(() => _listening = false);
      switch (parseCommand(text)) {
        case VoiceCommand.objects:
          await _select(ScanMode.objects);
          await _primary();
        case VoiceCommand.text:
          await _select(ScanMode.text);
          await _primary();
        case VoiceCommand.family:
          await _select(ScanMode.family);
          await _primary();
        case VoiceCommand.describe:
          await _describe();
        case VoiceCommand.distance:
          await _distance();
        case VoiceCommand.rupiah:
          await _rupiah();
        case VoiceCommand.repeat:
          await _say(_lastNarration.isEmpty
              ? 'Belum ada hasil untuk diulangi.'
              : _lastNarration);
        case VoiceCommand.stop:
          await _stop();
        case VoiceCommand.indoor:
        case VoiceCommand.outdoor:
          await _say(
              'Pengukuran jarak memakai model yang sama untuk dalam dan luar ruangan.');
        case VoiceCommand.unknown:
          await _say(
              'Perintah belum dikenali. Coba: pindai, tulisan, keluarga, jarak, atau jelaskan foto.');
      }
    } on PlatformException catch (error) {
      if (generation == _generation)
        await _say(error.message ?? 'Perintah suara belum tersedia.');
    } finally {
      if (mounted && generation == _generation)
        setState(() => _listening = false);
    }
  }

  Future<void> _askQwen() async {
    if (_busy || _listening) return;
    await _stop();
    final generation = _generation;
    if (!mounted) return;
    setState(() => _listening = true);
    try {
      final allowed = await _native.call<bool>('requestMicrophone');
      if (!mounted || generation != _generation) return;
      if (allowed != true) {
        setState(() => _listening = false);
        await _say('Izin mikrofon diperlukan untuk mengajukan pertanyaan.');
        return;
      }
    } on PlatformException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _listening = false);
      await _say(error.message ?? 'Mikrofon belum tersedia.');
      return;
    }
    if (mounted) {
      setState(() {
        _listening = true;
        _message = 'Ucapkan pertanyaan setelah mikrofon siap.';
      });
    }
    try {
      final answer =
          await _native.call<String>('askQwen', {'thinking': _qwenThinking});
      if (mounted && generation == _generation && answer != null) {
        setState(() => _listening = false);
        await _say(answer);
      }
    } on PlatformException catch (error) {
      if (mounted && generation == _generation) {
        await _say(
            error.message ?? 'Model di perangkat belum dapat menjawab.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _listening = false);
      }
    }
  }

  Future<void> _settings() async {
    await _stop();
    await _refresh();
    if (!mounted) return;
    final enabled = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) =>
            SettingsPage(native: _native, status: _status, online: _online)));
    if (mounted && enabled != null) setState(() => _online = enabled);
    await _refresh();
  }

  Future<void> _family() async {
    await _stop();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => FamilyPage(native: _native)));
  }

  Future<void> _help() async {
    await _stop();
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Panduan penggunaan'),
              scrollable: true,
              content: const Text(usageGuide),
              actions: [
                TextButton(
                    onPressed: () async {
                      try {
                        await _native.speak(usageGuide);
                      } on PlatformException catch (_) {
                        // The complete guide remains readable with TalkBack.
                      }
                    },
                    child: const Text('Bacakan panduan')),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup panduan')),
              ],
            ));
    await _stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = _scanning
        ? 'Hentikan pindai'
        : switch (_mode) {
            ScanMode.objects => 'Mulai pindai',
            ScanMode.text => 'Baca tulisan',
            ScanMode.family => 'Kenali wajah'
          };
    return Scaffold(
      appBar: AppBar(
          title:
              const Text('IRIS', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
                tooltip: 'Panduan penggunaan',
                onPressed: _help,
                icon: const Icon(Icons.help_outline)),
            IconButton(
                tooltip: 'Pengaturan dan kesiapan model',
                onPressed: _settings,
                icon: const Icon(Icons.tune_rounded))
          ]),
      body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
            Row(children: [
              Icon(_online ? Icons.cloud_outlined : Icons.shield_outlined,
                  size: 18, color: const Color(0xff80efce)),
              const SizedBox(width: 8),
              Expanded(
                  child: Semantics(
                      label: _online
                          ? 'Mode online. Foto dikirim hanya atas permintaan.'
                          : 'Mode di perangkat. Semua proses berjalan di telepon.',
                      child: ExcludeSemantics(
                          child: Text(
                              _online
                                  ? 'ONLINE · FOTO ATAS PERMINTAAN'
                                  : 'DI PERANGKAT · TANPA UNGGAH FOTO',
                              style: const TextStyle(
                                  fontSize: 13,
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.bold)))))
            ]),
            const SizedBox(height: 20),
            const Text('Kenali sekitar.\nDengarkan hasilnya.',
                style: TextStyle(
                    fontSize: 30, height: 1.15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Arahkan kamera, pilih yang ingin Anda kenali.',
                style: TextStyle(color: Color(0xffb5c8d0), fontSize: 16)),
            const SizedBox(height: 22),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final mode in ScanMode.values)
                ChoiceChip(
                    showCheckmark: false,
                    selected: _mode == mode,
                    padding: const EdgeInsets.all(12),
                    avatar: Icon(
                        switch (mode) {
                          ScanMode.objects => Icons.center_focus_strong,
                          ScanMode.text => Icons.text_fields,
                          ScanMode.family => Icons.people_outline
                        },
                        size: 20),
                    label: Text(switch (mode) {
                      ScanMode.objects => 'Objek',
                      ScanMode.text => 'Tulisan',
                      ScanMode.family => 'Keluarga'
                    }),
                    onSelected: (_) => _select(mode)),
            ]),
            const SizedBox(height: 16),
            ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                    height: 230,
                    child: Stack(fit: StackFit.expand, children: [
                      if (_cameraAllowed)
                        const CameraPreview()
                      else
                        Container(
                            color: const Color(0xff172930),
                            child: Center(
                                child: TextButton.icon(
                                    onPressed: () async {
                                      try {
                                        await _ensureCamera();
                                      } on PlatformException catch (e) {
                                        _show(e.message ??
                                            'Kamera tidak tersedia.');
                                      }
                                    },
                                    icon: const Icon(Icons.camera_alt_outlined),
                                    label: const Text('Aktifkan kamera')))),
                      const ExcludeSemantics(
                          child: IgnorePointer(
                              child: Center(
                                  child: Icon(Icons.crop_free_rounded,
                                      size: 100, color: Colors.white70)))),
                      Positioned(
                          left: 14,
                          bottom: 14,
                          child: Semantics(
                              label: _scanning
                                  ? 'Pemindaian aktif'
                                  : 'Kamera belakang siap',
                              child: ExcludeSemantics(
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: Text(_scanning
                                          ? '● Pemindaian aktif'
                                          : 'Kamera belakang'))))),
                    ]))),
            const SizedBox(height: 16),
            _gated(FilledButton.icon(
                onPressed: _busy || _listening ? null : _primary,
                icon: Icon(
                    _scanning ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(primary))),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _gated(OutlinedButton.icon(
                  onPressed: _busy || _listening ? null : _distance,
                  icon: const Icon(Icons.straighten),
                  label: const Text('Ukur jarak'))),
              _gated(OutlinedButton.icon(
                  onPressed: _busy || _listening ? null : _listen,
                  icon: const Icon(Icons.mic_none),
                  label: const Text('Perintah'))),
              _gated(OutlinedButton.icon(
                  onPressed: _busy || _listening ? null : _rupiah,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Baca rupiah'))),
            ]),
            const SizedBox(height: 18),
            Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: const Color(0xff172930),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xff2b454e))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.graphic_eq, color: Color(0xff80efce)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Semantics(
                                header: true,
                                label: 'Hasil pembacaan',
                                child: const ExcludeSemantics(
                                    child: Text('HASIL PEMBACAAN',
                                        style: TextStyle(
                                            fontSize: 13,
                                            letterSpacing: 1.3,
                                            fontWeight: FontWeight.bold))))),
                        if (_busy || _listening)
                          SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: _listening
                                      ? 'Mikrofon sedang merekam'
                                      : 'Sedang memproses permintaan'))
                      ]),
                      const SizedBox(height: 14),
                      Semantics(
                          liveRegion: _announceMessage,
                          child: Text(_message,
                              style:
                                  const TextStyle(fontSize: 20, height: 1.45))),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, children: [
                        _gated(TextButton.icon(
                            onPressed: _busy || _listening
                                ? null
                                : () => _say(_lastNarration.isEmpty
                                    ? 'Belum ada hasil.'
                                    : _lastNarration),
                            icon: const Icon(Icons.replay),
                            label: const Text('Ulangi'))),
                        TextButton.icon(
                            onPressed: _stop,
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('Berhenti'))
                      ]),
                    ])),
            const SizedBox(height: 12),
            _gated(OutlinedButton.icon(
                onPressed: _busy || _listening ? null : _describe,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Jelaskan foto'))),
            const SizedBox(height: 12),
            _gated(SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mode berpikir lebih lama'),
                subtitle: Text(_qwenThinking
                    ? 'Aktif: jawaban lebih dipikirkan dan lebih lama'
                    : 'Nonaktif: jawaban langsung dan singkat'),
                value: _qwenThinking,
                onChanged: _busy || _listening
                    ? null
                    : (value) => setState(() => _qwenThinking = value))),
            _gated(FilledButton.icon(
                onPressed: _busy || _listening ? null : _askQwen,
                icon: const Icon(Icons.psychology_alt_outlined),
                label: const Text('Tanya dengan suara'))),
            const SizedBox(height: 8),
            TextButton.icon(
                onPressed: _family,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Kelola wajah keluarga')),
            const SizedBox(height: 8),
            const Text(
                'Jarak adalah estimasi kamera. Hasil penelitian belum menggantikan alat bantu mobilitas.',
                style: TextStyle(fontSize: 14, color: Color(0xffb5c8d0))),
          ])),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage(
      {super.key,
      required this.native,
      required this.status,
      required this.online});
  final NativeBridge native;
  final Map<Object?, Object?> status;
  final bool online;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _key = TextEditingController();
  late final TextEditingController _model =
      TextEditingController(text: widget.status['gptModel'] as String? ?? '');
  late bool _online = widget.online;
  String _notice = '';
  Future<void> _save() async {
    try {
      await widget.native.call<void>('saveSettings',
          {'apiKey': _key.text.trim(), 'model': _model.text.trim()});
      if (mounted) Navigator.pop(context, _online);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _notice = e.message ?? 'Gagal menyimpan.');
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final models =
        Map<Object?, Object?>.from(widget.status['models'] as Map? ?? {});
    return Scaffold(
        appBar: AppBar(title: const Text('Pengaturan')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Kesiapan model di perangkat',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          for (final name in {
            'objects': 'Deteksi objek',
            'face': 'Pengenalan keluarga',
            'depth': 'Perkiraan jarak',
            'speech': 'Perintah suara',
            'qwen': 'Model bahasa di perangkat'
          }.entries)
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(models[name.key] == true
                    ? Icons.check_circle_outline
                    : Icons.download_for_offline_outlined),
                title: Text(name.value),
                subtitle: Text(models[name.key] == true
                    ? 'Model tersedia'
                    : 'Model belum dipasang dalam paket aplikasi')),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.record_voice_over_outlined),
              title: const Text('Suara Bahasa Indonesia'),
              subtitle: Text(widget.status['ttsReady'] == true
                  ? 'Suara di perangkat siap'
                  : 'Pasang suara Bahasa Indonesia pada pengaturan telepon')),
          OutlinedButton(
              onPressed: () => widget.native.call<void>('ttsSettings'),
              child: const Text('Buka pengaturan suara telepon')),
          const SizedBox(height: 24),
          const Text('Penjelasan oleh layanan online',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Izinkan mode online'),
              subtitle: const Text(
                  'Hanya tombol Jelaskan foto yang mengirim gambar ke layanan online. Mode ini kembali diproses di perangkat ketika aplikasi dibuka ulang.'),
              value: _online,
              onChanged: (value) => setState(() => _online = value)),
          const SizedBox(height: 12),
          TextField(
              controller: _model,
              decoration: const InputDecoration(
                  labelText: 'Model online dengan dukungan gambar',
                  hintText: 'Isi model ID yang tersedia pada akun Anda'),
              autocorrect: false),
          const SizedBox(height: 16),
          TextField(
              controller: _key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                  labelText: widget.status['hasApiKey'] == true
                      ? 'API key baru (kosong = pertahankan)'
                      : 'API key layanan online')),
          const SizedBox(height: 12),
          const Text(
              'Kunci disimpan terenkripsi di HP untuk demo pribadi. Jangan membagikan kunci atau memasukkannya ke kode sumber.'),
          TextButton(
              onPressed: () async {
                await widget.native.call<void>('deleteApiKey');
                if (mounted) setState(() => _notice = 'API key dihapus.');
              },
              child: const Text('Hapus API key tersimpan')),
          if (_notice.isNotEmpty) Text(_notice),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _save, child: const Text('Simpan pengaturan')),
          const SizedBox(height: 20),
          OutlinedButton(
              onPressed: () async {
                final path = await widget.native.call<String>('exportMetrics');
                if (mounted)
                  setState(() => _notice = path ?? 'Ekspor dibatalkan.');
              },
              child: const Text('Ekspor metrik penelitian (CSV)')),
        ]));
  }
}

class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key, required this.native});
  final NativeBridge native;
  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  final _name = TextEditingController();
  List<Map<Object?, Object?>> _profiles = [];
  String _message =
      'Daftarkan 5 foto dengan arah wajah berbeda. Sistem akan menyebutkan arahan lewat suara.';
  int _count = 0;
  bool _busy = false;
  bool _announceMessage = false;
  bool _cameraAllowed = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Widget _gated(Widget child) => MergeSemantics(
      child: Semantics(
          hint: _busy
              ? 'Belum dapat dipakai, pemeriksaan wajah sedang berjalan'
              : null,
          child: child));

  Future<void> _load() async {
    var allowed = _cameraAllowed;
    try {
      allowed = (await widget.native.status())['cameraPermission'] == true;
    } on PlatformException catch (_) {
    } on MissingPluginException {}
    final profiles = await widget.native.call<List>('listFamily') ?? [];
    if (mounted)
      setState(() {
        _cameraAllowed = allowed;
        _profiles =
            profiles.map((p) => Map<Object?, Object?>.from(p as Map)).toList();
      });
  }

  Future<void> _ensureCamera() async {
    var allowed = false;
    String? failure;
    try {
      allowed = await widget.native.call<bool>('requestCamera') ?? false;
      if (!allowed)
        failure =
            'Izin kamera diperlukan. Aktifkan melalui pengaturan aplikasi.';
    } on PlatformException catch (e) {
      failure = e.message ?? 'Kamera tidak tersedia.';
    }
    if (!mounted) return;
    setState(() {
      _cameraAllowed = allowed;
      if (failure != null) {
        _message = failure;
        _announceMessage = true;
      }
    });
  }

  Future<void> _capture() async {
    if (_name.text.trim().isEmpty) {
      setState(() {
        _message = 'Isi nama panggilan terlebih dahulu.';
        _announceMessage = true;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final allowed = await widget.native.call<bool>('requestCamera') ?? false;
      if (mounted) setState(() => _cameraAllowed = allowed);
      if (!allowed)
        throw PlatformException(
            code: 'permission', message: 'Izin kamera diperlukan.');
      final count = await widget.native
              .call<int>('enrollFace', {'name': _name.text.trim()}) ??
          0;
      if (mounted)
        setState(() {
          _count = count;
          _announceMessage = false;
          _message = count == 5
              ? 'Profil tersimpan. Anda dapat mengenali wajah ini di perangkat.'
              : 'Foto $count dari 5 diterima. Ubah sedikit arah wajah untuk foto berikutnya.';
        });
      await widget.native.speak(_message);
      if (count == 5) {
        _name.clear();
        _count = 0;
        await _load();
      }
    } on PlatformException catch (e) {
      if (mounted)
        setState(() {
          _message = e.message ?? 'Wajah belum dapat didaftarkan.';
          _announceMessage = true;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    unawaited(widget.native.call<void>('cancelEnrollment'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Wajah keluarga')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Kenali orang terdekat',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text(
            'Daftarkan dengan sepengetahuan orang tersebut. Data wajah disimpan di HP dan bisa dihapus kapan saja.'),
        const SizedBox(height: 16),
        SizedBox(
            height: 230,
            child: _cameraAllowed
                ? const CameraPreview()
                : ColoredBox(
                    color: const Color(0xff172930),
                    child: Center(
                        child: TextButton.icon(
                            onPressed: _ensureCamera,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Aktifkan kamera'))))),
        const SizedBox(height: 16),
        TextField(
            controller: _name,
            enabled: !_busy && _count == 0,
            maxLength: 40,
            decoration: const InputDecoration(
                labelText: 'Nama panggilan, misalnya Istri')),
        _gated(FilledButton.icon(
            onPressed: _busy ? null : _capture,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(_busy
                ? 'Memeriksa wajah…'
                : 'Ambil foto ${_count + 1} dari 5'))),
        const SizedBox(height: 12),
        Semantics(
            liveRegion: _announceMessage,
            child: Text(_message, style: const TextStyle(fontSize: 17))),
        _gated(TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await widget.native.call<void>('cancelEnrollment');
                    if (mounted)
                      setState(() {
                        _count = 0;
                        _message = 'Pendaftaran dibatalkan.';
                        _announceMessage = true;
                      });
                  },
            child: const Text('Batalkan pendaftaran'))),
        const Divider(height: 32),
        if (_profiles.isEmpty) const Text('Belum ada keluarga terdaftar.'),
        for (final profile in _profiles)
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(profile['name'] as String),
              trailing: IconButton(
                  tooltip: 'Hapus ${profile['name']}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                                title: const Text('Hapus profil wajah?'),
                                content: Text(
                                    'Data ${profile['name']} akan dihapus dari HP.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Batal')),
                                  FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Hapus'))
                                ]));
                    if (confirmed == true) {
                      await widget.native
                          .call<void>('deleteFamily', {'id': profile['id']});
                      await _load();
                    }
                  })),
      ]));
}
