import 'package:flutter/material.dart';

/// A full photo from a signed link, loaded in the background: a spinner while it arrives and,
/// if it can't be loaded (no connection, expired link), a message with a way to try again
/// instead of a blank or broken image.
class NetworkPhoto extends StatefulWidget {
  const NetworkPhoto({super.key, required this.url, this.fit = BoxFit.cover, this.compact = false});
  final String url;
  final BoxFit fit;

  /// Small slot (a strip thumbnail): icon only, no text.
  final bool compact;

  @override
  State<NetworkPhoto> createState() => _NetworkPhotoState();
}

class _NetworkPhotoState extends State<NetworkPhoto> {
  int _try = 0;

  @override
  Widget build(BuildContext context) => Image.network(
        widget.url,
        key: ValueKey('${widget.url}#$_try'),
        fit: widget.fit,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const ColoredBox(color: Color(0xFF2E3640), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))),
        errorBuilder: (_, _, _) => GestureDetector(
          onTap: () => setState(() => _try++),
          child: ColoredBox(
            color: const Color(0xFF2E3640),
            child: Center(
              child: widget.compact
                  ? const Icon(Icons.refresh, size: 18, color: Colors.white70)
                  : const Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.broken_image_outlined, color: Colors.white70),
                      SizedBox(height: 4),
                      Text("Couldn't load the photo · tap to retry",
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white70)),
                    ]),
            ),
          ),
        ),
      );
}

/// The small picture on a scan row: photo 1 of the scan, cropped to a square without
/// stretching. Shows a spinner while it loads, and the neutral dark tile (the old placeholder)
/// when the scan has no photo or the link can't be loaded (expired, offline).
class ScanThumb extends StatelessWidget {
  const ScanThumb({super.key, required this.url, this.faded = false, this.size = 40});
  final String? url;
  final bool faded;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: faded ? const Color(0xFF4A2A2A) : const Color(0xFF1F1F23),
      child: const Center(child: Icon(Icons.image_not_supported_outlined, size: 18, color: Colors.white54)),
    );
    return Opacity(
      opacity: faded ? 0.6 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: size,
          height: size,
          child: url == null
              ? fallback
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  // Decode at thumbnail size, not the full photo.
                  cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const ColoredBox(
                          color: Color(0xFF1F1F23),
                          child: Center(
                            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
                          ),
                        ),
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
