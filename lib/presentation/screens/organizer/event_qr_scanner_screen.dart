import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../domain/models/event.dart';
import '../../../presentation/providers/offline_qr_providers.dart';
import '../../../presentation/providers/organizer_events_providers.dart';
import '../../../presentation/providers/organizer_wallet_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';

class EventQrScannerScreen extends ConsumerStatefulWidget {
  const EventQrScannerScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<EventQrScannerScreen> createState() =>
      _EventQrScannerScreenState();
}

class _EventQrScannerScreenState extends ConsumerState<EventQrScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  var _busy = false;
  var _rosterReady = false;
  var _rosterFromCache = false;
  var _hasRoster = false;
  String? _error;
  String? _eventTitle;
  AttendanceConfirmResult? _success;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final events = ref.read(myOrganizerEventsProvider).valueOrNull;
    final fromList = events?.where((e) => e.id == widget.eventId).firstOrNull;
    final title = fromList?.title;

    final service = ref.read(offlineAttendanceServiceProvider);
    if (service == null) {
      if (mounted) {
        setState(() {
          _rosterReady = true;
          _eventTitle = title;
        });
      }
      return;
    }

    await service.syncPending();
    final fetched = await service.prefetchRoster(
      eventId: widget.eventId,
      eventTitle: title ?? 'Мероприятие',
    );
    final cached = fetched.roster ?? service.cachedRoster(widget.eventId);
    if (!mounted) return;
    setState(() {
      _rosterReady = true;
      _rosterFromCache = !fetched.fromNetwork;
      _hasRoster = cached != null && cached.participants.isNotEmpty;
      _eventTitle = cached?.eventTitle ?? title;
    });
    bumpPendingAttendanceTick(ref);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _success != null) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null || raw.isEmpty) return;

    final token = EventRepository.parseQrToken(raw);
    if (token == null) {
      setState(() => _error = 'Неверный QR-код');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    await _controller.stop();

    try {
      final service = ref.read(offlineAttendanceServiceProvider);
      final AttendanceConfirmResult result;
      if (service != null) {
        result = await service.confirm(
          eventId: widget.eventId,
          publicQrId: token,
          eventTitleHint: _eventTitle,
        );
      } else {
        result = await ref.read(eventRepositoryProvider).confirmAttendance(
              eventId: widget.eventId,
              publicQrId: token,
            );
      }
      ref.invalidate(eventParticipantsProvider(widget.eventId));
      ref.invalidate(myOrganizerEventsProvider);
      ref.invalidate(organizerWalletProvider);
      ref.invalidate(organizerTransactionsProvider);
      ref.invalidate(organizerDashboardProvider);
      bumpPendingAttendanceTick(ref);
      if (!mounted) return;
      setState(() {
        _success = result;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorMapper.map(e);
        _busy = false;
      });
      await _controller.start();
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _success = null;
      _error = null;
    });
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    if (_success != null) {
      return _SuccessView(
        result: _success!,
        onDone: () => context.pop(),
        onScanAgain: _scanAgain,
      );
    }

    final pending = ref.watch(pendingAttendanceCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Сканирование участника')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ScanFramePainter(),
                    child: const SizedBox.expand(),
                  ),
                ),
                if (_busy)
                  const ColoredBox(
                    color: Color(0x880A0B0D),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Column(
              children: [
                Text(
                  !_rosterReady
                      ? 'Подготовка списка участников…'
                      : (!_hasRoster
                          ? 'Нет списка участников. Нужен интернет один раз перед полигоном.'
                          : (_rosterFromCache
                              ? 'Офлайн-режим: список участников из кэша'
                              : 'Наведите камеру на QR-код участника')),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
                if (pending > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ожидает синхронизации: $pending',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.danger,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.result,
    required this.onDone,
    required this.onScanAgain,
  });

  final AttendanceConfirmResult result;
  final VoidCallback onDone;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm', 'ru').format(result.attendedAt.toLocal());
    final pending = result.pendingSync;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Подтверждение')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          AppCard(
            accentBorder: true,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accentDim),
                  ),
                  child: Icon(
                    pending ? Icons.cloud_off_outlined : Icons.check_rounded,
                    color: AppColors.accent,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  pending
                      ? 'Сохранено офлайн'
                      : 'Участие подтверждено',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                if (pending) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Начисление CR синхронизируется при появлении интернета',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  result.nickname,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  result.city,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.borderSubtle, height: 1),
                const SizedBox(height: 14),
                _Line(label: 'Мероприятие', value: result.eventTitle),
                const SizedBox(height: 8),
                _Line(label: 'Время', value: time),
                if (!pending) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadii.badge),
                      border: Border.all(color: AppColors.accentDim),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Начислено ${result.rewardLabel}',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Баланс: ${result.balanceLabel}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppButton(label: 'Готово', onPressed: onDone),
          const SizedBox(height: 8),
          AppButton(
            label: 'Сканировать ещё',
            variant: AppButtonVariant.secondary,
            onPressed: onScanAgain,
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12.5,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = const Color(0x990A0B0D);
    final holeSize = size.shortestSide * 0.62;
    final left = (size.width - holeSize) / 2;
    final top = (size.height - holeSize) / 2;
    final hole = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, holeSize, holeSize),
      const Radius.circular(16),
    );

    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlay);

    final border = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(hole, border);

    final corner = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    const len = 22.0;
    canvas.drawLine(Offset(left, top + len), Offset(left, top), corner);
    canvas.drawLine(Offset(left, top), Offset(left + len, top), corner);
    canvas.drawLine(
      Offset(left + holeSize - len, top),
      Offset(left + holeSize, top),
      corner,
    );
    canvas.drawLine(
      Offset(left + holeSize, top),
      Offset(left + holeSize, top + len),
      corner,
    );
    canvas.drawLine(
      Offset(left, top + holeSize - len),
      Offset(left, top + holeSize),
      corner,
    );
    canvas.drawLine(
      Offset(left, top + holeSize),
      Offset(left + len, top + holeSize),
      corner,
    );
    canvas.drawLine(
      Offset(left + holeSize - len, top + holeSize),
      Offset(left + holeSize, top + holeSize),
      corner,
    );
    canvas.drawLine(
      Offset(left + holeSize, top + holeSize - len),
      Offset(left + holeSize, top + holeSize),
      corner,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
