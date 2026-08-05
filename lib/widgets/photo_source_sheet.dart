import 'package:flutter/material.dart';

enum PhotoSourceChoice { camera, gallery }

class PhotoSourceSheet extends StatelessWidget {
  const PhotoSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '添加照片',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ListTile(
              minTileHeight: 72,
              leading: const Icon(Icons.camera_alt_outlined, size: 32),
              title: const Text('相机拍照'),
              subtitle: const Text('使用 App 内置相机，录音会继续'),
              onTap: () => Navigator.pop(context, PhotoSourceChoice.camera),
            ),
            ListTile(
              minTileHeight: 72,
              leading: const Icon(Icons.photo_library_outlined, size: 32),
              title: const Text('从相册导入'),
              subtitle: const Text('选择一张已有照片，录音会继续'),
              onTap: () => Navigator.pop(context, PhotoSourceChoice.gallery),
            ),
          ],
        ),
      ),
    );
  }
}
