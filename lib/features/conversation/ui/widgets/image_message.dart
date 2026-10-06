import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../data/repositories/media_repository.dart';
import '../../domain/models/timeline_item.dart';
import '../image/view_models/image_state.dart';
import '../image/view_models/image_view_model.dart';

const kImageMaxSide = 320.0;

const _unknownSize = Size(240, 180);

Size? imageBoxSize(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  final scale = min(1.0, kImageMaxSide / max(width, height));
  return Size(width * scale, height * scale);
}

class ImageMessage extends StatefulWidget {
  const ImageMessage({super.key, required this.image, this.alignEnd = false});

  final ImageContent image;

  final bool alignEnd;

  @override
  State<ImageMessage> createState() => _ImageMessageState();
}

class _ImageMessageState extends State<ImageMessage> {
  late final _viewModel = ImageViewModel(
    context.read<MediaRepository>(),
    widget.image.media,
    thumbnail: true,
  )..load();

  @override
  void didUpdateWidget(ImageMessage old) {
    super.didUpdateWidget(old);
    if (old.image.media != widget.image.media) {
      _viewModel.show(widget.image.media);
    }
  }

  @override
  void dispose() {
    _viewModel.close();
    super.dispose();
  }

  void _open(Uint8List? preview) => showImageViewer(
    context,
    image: widget.image,
    preview: preview,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final image = widget.image;
    final caption = image.caption;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        BlocBuilder<ImageViewModel, ImageState>(
          bloc: _viewModel,
          builder: (context, state) => _ImageFrame(
            image: image,
            state: state,
            onOpen: _open,
            onRetry: _viewModel.load,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            textAlign: widget.alignEnd ? TextAlign.end : TextAlign.start,
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontSize: 17,
              height: 1.4,
              color: colors.textPrimary,
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageFrame extends StatelessWidget {
  const _ImageFrame({
    required this.image,
    required this.state,
    required this.onOpen,
    required this.onRetry,
  });

  final ImageContent image;

  final ImageState state;

  final ValueChanged<Uint8List?> onOpen;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = imageBoxSize(image.width, image.height);
    final bytes = state.bytes;
    final Widget content = switch (state.status) {
      ImageStatus.failed => _Broken(onRetry: onRetry),
      _ when bytes == null => ColoredBox(
        key: const Key('image_loading'),
        color: colors.surfaceHigh,
        child: const Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      _ => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const Key('image_open'),
          onTap: () => onOpen(bytes),
          child: Image.memory(
            bytes,
            fit: size == null ? BoxFit.contain : BoxFit.cover,
            cacheWidth: size == null
                ? null
                : (size.width * MediaQuery.devicePixelRatioOf(context)).ceil(),
            gaplessPlayback: true,
            semanticLabel: image.filename,
            errorBuilder: (context, error, stack) =>
                const _Broken(onRetry: null),
          ),
        ),
      ),
    };
    final showsImage = state.status != ImageStatus.failed && bytes != null;
    return Tooltip(
      message: image.filename,
      waitDuration: const Duration(milliseconds: 600),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: switch (size) {
          final size? => SizedBox.fromSize(size: size, child: content),
          null when showsImage => ConstrainedBox(
            constraints: BoxConstraints.loose(
              const Size.square(kImageMaxSide),
            ),
            child: content,
          ),
          null => SizedBox.fromSize(size: _unknownSize, child: content),
        },
      ),
    );
  }
}

class _Broken extends StatelessWidget {
  const _Broken({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      key: const Key('image_error'),
      color: colors.surfaceHigh,
      child: InkWell(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image_outlined, color: colors.textMuted),
              const SizedBox(height: 6),
              Text(
                onRetry == null
                    ? 'Imagem inválida'
                    : 'Não foi possível carregar · tentar de novo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showImageViewer(
  BuildContext context, {
  required ImageContent image,
  Uint8List? preview,
}) {
  final repository = context.read<MediaRepository>();
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xEB000000),
    barrierLabel: 'Fechar imagem',
    builder: (context) => _ImageViewer(
      repository: repository,
      image: image,
      preview: preview,
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({
    required this.repository,
    required this.image,
    required this.preview,
  });

  final MediaRepository repository;

  final ImageContent image;

  final Uint8List? preview;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final _viewModel = ImageViewModel(
    widget.repository,
    widget.image.media,
    thumbnail: false,
    placeholder: widget.preview,
  )..load();

  @override
  void dispose() {
    _viewModel.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const light = Color(0xFFEDEDED);
    void close() => Navigator.of(context).pop();
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: Material(
          key: const Key('image_viewer'),
          type: MaterialType.transparency,
          child: BlocBuilder<ImageViewModel, ImageState>(
            bloc: _viewModel,
            builder: (context, state) => Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('image_viewer_backdrop'),
                    behavior: HitTestBehavior.opaque,
                    onTap: close,
                    child: switch (state.bytes) {
                      final bytes? => InteractiveViewer(
                        maxScale: 8,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {},
                            child: Image.memory(
                              bytes,
                              gaplessPlayback: true,
                              semanticLabel: widget.image.filename,
                            ),
                          ),
                        ),
                      ),
                      null when state.status == ImageStatus.loading =>
                        const Center(
                          child: CircularProgressIndicator(color: light),
                        ),
                      null => const SizedBox(),
                    },
                  ),
                ),
                if (state.status == ImageStatus.failed)
                  const Positioned(
                    left: 24,
                    right: 24,
                    bottom: 64,
                    child: Text(
                      'Não foi possível carregar a imagem original.',
                      key: Key('image_viewer_error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: light, fontSize: 14),
                    ),
                  ),
                if (state.status == ImageStatus.loading && state.bytes != null)
                  const Positioned(
                    top: 22,
                    left: 22,
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: light,
                      ),
                    ),
                  ),
                Positioned(
                  left: 24,
                  right: 80,
                  bottom: 24,
                  child: Text(
                    widget.image.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: light, fontSize: 13),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    key: const Key('image_viewer_close'),
                    tooltip: 'Fechar (Esc)',
                    onPressed: close,
                    color: light,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
