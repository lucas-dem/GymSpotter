import 'package:flutter/material.dart';

import '../state/fit_state.dart';
import '../theme/app_colors.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    final bytes = fit.profilePhoto;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: gc.accentSoft, shape: BoxShape.circle),
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: gc.border),
      ),
      child: bytes == null
          ? Icon(Icons.person_rounded, size: size * 0.56, color: gc.textSecondary)
          : Image(image: MemoryImage(bytes), fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}
