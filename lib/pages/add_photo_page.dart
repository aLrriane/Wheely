import 'dart:io' as dart_io;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../bsu_data.dart';

class AddPhotoPage extends StatefulWidget {
  const AddPhotoPage({super.key, required this.place});

  final Place place;

  @override
  State<AddPhotoPage> createState() => _AddPhotoPageState();
}

class _AddPhotoPageState extends State<AddPhotoPage> {
  final List<String> _photos = []; // local file paths for now, backend later
  final ImagePicker _picker = ImagePicker();

  Future<void> _takePhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() => _photos.add(picked.path));
    }
  }

  Future<void> _pickFromGallery() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _photos.add(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Photo'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _photos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.photo_library_outlined, size: 64, color: Colors.black38),
                          const SizedBox(height: 12),
                          const Text('No photos yet. Add one below.'),
                          const SizedBox(height: 4),
                          const Text('Photos are only for presentation until the backend is ready.'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _photos.length,
                      itemBuilder: (context, i) {
                        final file = dart_io.File(_photos[i]);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              file,
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            onPressed: _takePhoto,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            onPressed: _pickFromGallery,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlue.shade100,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          // frontend only: upload would go to places/{id}/photos later
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Photo upload coming soon')),
                          );
                        },
                        child: const Text('Save photos'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
