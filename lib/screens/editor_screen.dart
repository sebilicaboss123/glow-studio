import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../edit/adjustments.dart';
import '../edit/image_ops.dart';
import '../widgets/adjust_slider.dart';
import '../widgets/filter_strip.dart';

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

  /// The clean preview as imported (color unmodified).
  late Uint8List _basePreview;

  /// Preview after skin smoothing is applied (color still unmodified).
  late Uint8List _smoothedPreview;

  double _renderedSmooth = 0;
  Timer? _smoothDebounce;
  bool _smoothing = false;
  bool _exporting = false;
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _basePreview = widget.prepared.preview;
    _smoothedPreview = widget.prepared.preview;
  }

  @override
  void dispose() {
    _smoothDebounce?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _update(Adjustments next) {
    setState(() => _adj = next);
    if (next.smooth != _renderedSmooth) {
      _scheduleSmooth(next.smooth);
    }
  }

  void _scheduleSmooth(double amount) {
    _smoothDebounce?.cancel();
    _smoothDebounce = Timer(const Duration(milliseconds: 160), () async {
      setState(() => _smoothing = true);
      try {
        final bytes = amount <= 0.001
            ? _basePreview
            : await smoothPreview(_basePreview, amount);
        if (!mounted) return;
        setState(() {
          _smoothedPreview = bytes;
          _renderedSmooth = amount;
          _smoothing = false;
        });
      } catch (_) {
        if (mounted) setState(() => _smoothing = false);
      }
    });
  }

  Future<void> _save() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final original = await File(widget.prepared.sourcePath).readAsBytes();
      final jpg = await renderExport(original, _adj);
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
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

  void _reset() => _update(const Adjustments());

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
            onPressed: _adj.isNeutral ? null : _reset,
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
                : FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('Save'),
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
    final bytes = _showOriginal ? _basePreview : _smoothedPreview;
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
            if (_smoothing)
              Positioned(
                top: 12,
                right: 12,
                child: _pill(scheme, 'Smoothing…'),
              ),
            if (_showOriginal)
              Positioned(
                bottom: 12,
                child: _pill(scheme, 'Original'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(ColorScheme scheme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
    );
  }

  Widget _controls(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabs,
              labelColor: scheme.primary,
              indicatorColor: scheme.primary,
              tabs: const [
                Tab(text: 'Light'),
                Tab(text: 'Skin'),
                Tab(text: 'Filters'),
              ],
            ),
            SizedBox(
              height: 190,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _lightTab(),
                  _skinTab(),
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
          onChanged: (v) => _update(_adj.copyWith(brightness: v)),
        ),
        AdjustSlider(
          label: 'Contrast',
          value: _adj.contrast,
          onChanged: (v) => _update(_adj.copyWith(contrast: v)),
        ),
        AdjustSlider(
          label: 'Saturation',
          value: _adj.saturation,
          onChanged: (v) => _update(_adj.copyWith(saturation: v)),
        ),
        AdjustSlider(
          label: 'Warmth',
          value: _adj.warmth,
          onChanged: (v) => _update(_adj.copyWith(warmth: v)),
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
            onChanged: (v) => _update(_adj.copyWith(smooth: v)),
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

  Widget _filtersTab() {
    return FilterStrip(
      preview: _basePreview,
      selected: _adj.filter,
      onSelected: (f) => _update(_adj.copyWith(filter: f)),
    );
  }
}
