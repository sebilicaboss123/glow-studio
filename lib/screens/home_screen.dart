import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../edit/image_ops.dart';
import '../edit/prepared_image.dart';
import '../theme.dart';
import 'editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 4000,
        imageQuality: 100,
      );
      if (file == null) {
        setState(() => _busy = false);
        return;
      }
      final Uint8List bytes = await File(file.path).readAsBytes();
      final PreviewData preview = await buildPreview(bytes);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EditorScreen(
            prepared: PreparedImage(
              preview: preview.bytes,
              width: preview.width,
              height: preview.height,
              sourcePath: file.path,
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open that photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlowBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 3),
                const _Hero(),
                const SizedBox(height: 28),
                const Text(
                  'Glow Studio',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Retouch, reshape and glow —\nright on your phone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                const Spacer(flex: 4),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                else ...[
                  GradientButton(
                    label: 'Choose a photo',
                    icon: Icons.photo_library_outlined,
                    onTap: () => _pick(ImageSource.gallery),
                  ),
                  const SizedBox(height: 14),
                  _GhostButton(
                    label: 'Take a photo',
                    icon: Icons.photo_camera_outlined,
                    onTap: () => _pick(ImageSource.camera),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Face-only editing · your photos never leave the device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: kBrandGradient,
        boxShadow: [
          BoxShadow(
            color: kPink.withValues(alpha: 0.45),
            blurRadius: 36,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.auto_awesome, size: 50, color: Colors.white),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
