import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Looping muted video that fades in over a still image. If the video can't
/// load (unsupported platform, decode error) the still image simply stays.
class VideoBackground extends StatefulWidget {
  const VideoBackground({
    super.key,
    required this.videoAsset,
    required this.fallbackImage,
    this.imageAlignment = Alignment.center,
    this.videoAlignment = Alignment.center,
  });

  final String videoAsset;
  final String fallbackImage;
  final Alignment imageAlignment;

  /// Which part of a landscape video stays visible in a portrait crop.
  final Alignment videoAlignment;

  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.asset(
      widget.videoAsset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      // Video is optional polish; the still image stays on screen.
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          widget.fallbackImage,
          fit: BoxFit.cover,
          alignment: widget.imageAlignment,
        ),
        AnimatedOpacity(
          opacity: _ready ? 1 : 0,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOut,
          child: controller == null
              ? const SizedBox.shrink()
              : FittedBox(
                  fit: BoxFit.cover,
                  alignment: widget.videoAlignment,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
        ),
      ],
    );
  }
}
