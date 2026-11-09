import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../edit/adjustments.dart';
import '../edit/face.dart';
import '../edit/face_geometry.dart';
import '../edit/glow.dart';
import '../edit/image_ops.dart';
import '../edit/makeup.dart';
import '../edit/prepared_image.dart';
import '../edit/reshape.dart';
import '../theme.dart';
import '../widgets/adjust_slider.dart';
import '../widgets/filter_strip.dart';
import '../widgets/makeup_controls.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.prepared});

  final PreparedImage prepared;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  Adjustments _adj = const Adjustments();
  Makeup _makeup = const Makeup();
  Glow _glow = const Glow();
  Reshape _reshape = const Reshape();

  late Uint8List _basePreview;
  late Uint8List _processed; // base + smoothing + makeup (no color grade)

  FaceGeometry _geom = const FaceGeometry.none();
  bool _detecting = false;
  bool _detectTried = false;

  Timer? _debounce;
  int _renderSeq = 0;
  bool _rendering = false;
  bool _exporting = false;
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index >= 2 && _tabs.index <= 4 && !_detectTried) {
        _runDetection();
      }
    });
    _basePreview = widget.prepared.preview;
    _processed = widget.prepared.preview;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  bool get _pipelineActive =>
      _adj.smooth > 0.001 ||
      !_makeup.isEmpty ||
      !_glow.isEmpty ||
      !_reshape.isEmpty;

  Future<void> _runDetection() async {
    _detectTried = true;
    setState(() => _detecting = true);
    try {
      final g = await FaceService.detect(
        _basePreview,
        widget.prepared.width,
        widget.prepared.height,
      );
      if (!mounted) return;
      setState(() {
        _geom = g;
        _detecting = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _geom = const FaceGeometry.none();
          _detecting = false;
        });
      }
    }
  }

  void _setAdjustments(Adjustments next) {
    final smoothChanged = next.smooth != _adj.smooth;
    setState(() => _adj = next);
    if (smoothChanged) _scheduleRender();
  }

  void _setMakeup(Makeup next) {
    setState(() => _makeup = next);
    _scheduleRender();
  }

  void _setReshape(Reshape next) {
    setState(() => _reshape = next);
    _scheduleRender();
  }

  void _setGlow(Glow next) {
    setState(() => _glow = next);
    _scheduleRender();
  }

  void _scheduleRender() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 170), () async {
      final seq = ++_renderSeq;
      setState(() => _rendering = true);
      try {
        final bytes = await renderPreview(
          _basePreview,
          _adj.smooth,
          _makeup,
          _glow,
          _reshape,
          _geom,
        );
        if (!mounted || seq != _renderSeq) return;
        setState(() {
          _processed = bytes;
          _rendering = false;
        });
      } catch (_) {
        if (mounted && seq == _renderSeq) setState(() => _rendering = false);
      }
    });
  }

  Future<void> _save() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final original = await File(widget.prepared.sourcePath).readAsBytes();
      final jpg =
          await renderExport(original, _adj, _makeup, _glow, _reshape, _geom);
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putImageBytes(jpg, album: 'Glow Studio');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to your gallery ✓')),
      );
    } on GalException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: ${e.type.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _reset() {
    setState(() {
      _adj = const Adjustments();
      _makeup = const Makeup();
      _glow = const Glow();
      _reshape = const Reshape();
      _processed = _basePreview;
    });
  }

  bool get _isNeutral =>
      _adj.isNeutral && _makeup.isEmpty && _glow.isEmpty && _reshape.isEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Edit'),
        actions: [
          IconButton(
            tooltip: 'Reset',
            onPressed: _isNeutral ? null : _reset,
            icon: const Icon(Icons.restart_alt),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _exporting
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : GradientButton(
                    label: 'Save',
                    icon: Icons.save_alt,
                    onTap: _save,
                    height: 40,
                    expand: false,
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _preview(scheme)),
          _controls(scheme),
        ],
      ),
    );
  }

  Widget _preview(ColorScheme scheme) {
    final matrix = _showOriginal
        ? const Adjustments().toColorMatrix()
        : _adj.toColorMatrix();
    final bytes = _showOriginal || !_pipelineActive ? _basePreview : _processed;
    return GestureDetector(
      onTapDown: (_) => setState(() => _showOriginal = true),
      onTapUp: (_) => setState(() => _showOriginal = false),
      onTapCancel: () => setState(() => _showOriginal = false),
      child: Container(
        color: Colors.black,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.matrix(matrix),
              child: Image.memory(bytes, gaplessPlayback: true, fit: BoxFit.contain),
            ),
            if (_rendering)
              Positioned(top: 14, right: 14, child: _pill('Rendering…', dot: true)),
            if (_showOriginal)
              Positioned(bottom: 16, child: _pill('Original'))
            else if (_pipelineActive)
              Positioned(
                bottom: 16,
                child: _pill('Hold to compare', icon: Icons.compare),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, {IconData? icon, bool dot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: kPink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
          ],
          if (icon != null) ...[
            Icon(icon, size: 13, color: Colors.white70),
            const SizedBox(width: 6),
          ],
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _controls(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 2),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
              indicator: BoxDecoration(
                color: kPink.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: kPink.withValues(alpha: 0.5)),
              ),
              tabs: const [
                Tab(text: 'Light'),
                Tab(text: 'Skin'),
                Tab(text: 'Makeup'),
                Tab(text: 'Shape'),
                Tab(text: 'Glow'),
                Tab(text: 'Filters'),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 214,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _lightTab(),
                  _skinTab(),
                  _makeupTab(),
                  _shapeTab(),
                  _glowTab(),
                  _filtersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lightTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        AdjustSlider(
          label: 'Brightness',
          value: _adj.brightness,
          onChanged: (v) => _setAdjustments(_adj.copyWith(brightness: v)),
        ),
        AdjustSlider(
          label: 'Contrast',
          value: _adj.contrast,
          onChanged: (v) => _setAdjustments(_adj.copyWith(contrast: v)),
        ),
        AdjustSlider(
          label: 'Saturation',
          value: _adj.saturation,
          onChanged: (v) => _setAdjustments(_adj.copyWith(saturation: v)),
        ),
        AdjustSlider(
          label: 'Warmth',
          value: _adj.warmth,
          onChanged: (v) => _setAdjustments(_adj.copyWith(warmth: v)),
        ),
      ],
    );
  }

  Widget _skinTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdjustSlider(
            label: 'Skin smoothing',
            value: _adj.smooth,
            min: 0,
            max: 1,
            onChanged: (v) => _setAdjustments(_adj.copyWith(smooth: v)),
          ),
          const SizedBox(height: 10),
          const Text(
            'Edge-aware: softens skin while keeping eyes, brows and lips sharp. '
            'Full quality is applied to the saved photo.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// Wraps a face-dependent tab with loading / no-face states.
  Widget _faceGate(Widget child) {
    if (_detecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text('Finding the face…',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }
    if (!_geom.hasFace) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.face_retouching_off, color: Colors.white38, size: 34),
              const SizedBox(height: 10),
              const Text(
                'No face detected in this photo.\nThis needs a clear, front-facing face.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _detecting ? null : _runDetection,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return child;
  }

  Widget _makeupTab() {
    return _faceGate(MakeupControls(makeup: _makeup, onChanged: _setMakeup));
  }

  Widget _shapeTab() {
    return _faceGate(
      ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          AdjustSlider(
            label: 'Face slim',
            value: _reshape.faceSlim,
            min: 0,
            max: 1,
            onChanged: (v) => _setReshape(_reshape.copyWith(faceSlim: v)),
          ),
          AdjustSlider(
            label: 'Eye size',
            value: _reshape.eyeSize,
            min: 0,
            max: 1,
            onChanged: (v) => _setReshape(_reshape.copyWith(eyeSize: v)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Subtle liquify around the detected landmarks. Keep it gentle for a '
            'natural look; full quality is applied on save.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _glowTab() {
    return _faceGate(
      ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          AdjustSlider(
            label: 'Radiance',
            value: _glow.radiance,
            min: 0,
            max: 1,
            onChanged: (v) => _setGlow(_glow.copyWith(radiance: v)),
          ),
          AdjustSlider(
            label: 'Under-eye',
            value: _glow.underEye,
            min: 0,
            max: 1,
            onChanged: (v) => _setGlow(_glow.copyWith(underEye: v)),
          ),
          AdjustSlider(
            label: 'Lip gloss',
            value: _glow.lipGloss,
            min: 0,
            max: 1,
            onChanged: (v) => _setGlow(_glow.copyWith(lipGloss: v)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Soft highlights placed on the cheekbones, under the eyes and the '
            'lower lip. Nothing outside the face is touched.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _filtersTab() {
    return FilterStrip(
      preview: _basePreview,
      selected: _adj.filter,
      onSelected: (f) => _setAdjustments(_adj.copyWith(filter: f)),
    );
  }
}
