import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

/// 图片存储服务 - 负责图片数据的文件系统存储
/// 将图片数据与元数据分离，大幅减少首次加载时间
class ImageStorageService {
  static final ImageStorageService _instance = ImageStorageService._internal();
  factory ImageStorageService() => _instance;
  ImageStorageService._internal();

  final Uuid _uuid = const Uuid();
  Directory? _imagesDirectory;

  /// 获取图片存储目录
  Future<Directory> _getImagesDirectory() async {
    if (_imagesDirectory != null) {
      return _imagesDirectory!;
    }

    Directory baseDir;
    
    // Windows: 使用 exe 所在目录
    if (Platform.isWindows) {
      // 获取可执行文件所在目录
      final executablePath = Platform.resolvedExecutable;
      final executableDir = File(executablePath).parent;
      baseDir = executableDir;
      print('ImageStorageService: Windows executable path: $executablePath');
      print('ImageStorageService: Windows base directory: ${baseDir.path}');
    }
    // macOS/Linux: 使用当前工作目录
    else {
      baseDir = Directory.current;
      print('ImageStorageService: Non-Windows base directory: ${baseDir.path}');
    }

    _imagesDirectory = Directory('${baseDir.path}/images');

    // 确保目录存在
    if (!await _imagesDirectory!.exists()) {
      await _imagesDirectory!.create(recursive: true);
      print('ImageStorageService: Created images directory: ${_imagesDirectory!.path}');
    }

    print('ImageStorageService: Images directory: ${_imagesDirectory!.path}');
    return _imagesDirectory!;
  }

  /// 保存图片数据到文件系统
  /// 返回图片引用ID
  Future<String> saveImage(Uint8List imageBytes) async {
    final imageId = _uuid.v4();
    final directory = await _getImagesDirectory();
    final file = File('${directory.path}/$imageId.png');

    print('ImageStorageService: 保存图片 $imageId，路径: ${file.path}，大小: ${imageBytes.length} 字节');
    await file.writeAsBytes(imageBytes);
    print('ImageStorageService: 图片 $imageId 保存成功');
    return imageId;
  }

  /// 根据图片引用ID加载图片数据
  Future<Uint8List?> loadImage(String imageRef) async {
    try {
      final directory = await _getImagesDirectory();
      final file = File('${directory.path}/$imageRef.png');

      print('ImageStorageService: loadImage - imageRef=$imageRef');
      print('ImageStorageService: loadImage - 目录=${directory.path}');
      print('ImageStorageService: loadImage - 文件路径=${file.path}');
      
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        print('ImageStorageService: loadImage - 图片加载成功，大小: ${bytes.length} 字节');
        return bytes;
      }
      
      print('ImageStorageService: loadImage - 图片文件不存在: ${file.path}');
      return null;
    } catch (e) {
      print('ImageStorageService: loadImage - 加载图片 $imageRef 异常: $e');
      return null;
    }
  }

  /// 删除指定图片
  Future<bool> deleteImage(String imageRef) async {
    try {
      final directory = await _getImagesDirectory();
      final file = File('${directory.path}/$imageRef.png');

      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      print('ImageStorageService: Error deleting image $imageRef: $e');
      return false;
    }
  }

  /// 批量删除图片
  Future<int> deleteImages(List<String> imageRefs) async {
    int deletedCount = 0;
    for (final ref in imageRefs) {
      if (await deleteImage(ref)) {
        deletedCount++;
      }
    }
    return deletedCount;
  }

  /// 清理所有图片文件
  Future<void> clearAllImages() async {
    try {
      final directory = await _getImagesDirectory();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        await directory.create(recursive: true);
      }
    } catch (e) {
      print('ImageStorageService: Error clearing images: $e');
    }
  }

  /// 获取存储的图片数量
  Future<int> getImageCount() async {
    try {
      final directory = await _getImagesDirectory();
      if (!await directory.exists()) {
        return 0;
      }
      final files = directory.listSync();
      return files.whereType<File>().length;
    } catch (e) {
      print('ImageStorageService: Error counting images: $e');
      return 0;
    }
  }

  /// 获取所有图片的总大小（字节）
  Future<int> getTotalStorageSize() async {
    try {
      final directory = await _getImagesDirectory();
      if (!await directory.exists()) {
        return 0;
      }
      int totalSize = 0;
      await for (final entity in directory.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      print('ImageStorageService: Error calculating storage size: $e');
      return 0;
    }
  }

  /// 检查图片是否存在
  Future<bool> imageExists(String imageRef) async {
    try {
      final directory = await _getImagesDirectory();
      final file = File('${directory.path}/$imageRef.png');
      return await file.exists();
    } catch (e) {
      print('ImageStorageService: Error checking image existence: $e');
      return false;
    }
  }

  /// 清理孤立的图片文件（没有元数据引用的图片）
  /// 需要传入所有有效的图片引用ID列表
  Future<int> cleanupOrphanedImages(List<String> validImageRefs) async {
    try {
      final directory = await _getImagesDirectory();
      if (!await directory.exists()) {
        return 0;
      }

      final validRefsSet = validImageRefs.toSet();
      int cleanedCount = 0;

      await for (final entity in directory.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          final imageRef = fileName.replaceAll('.png', '');

          if (!validRefsSet.contains(imageRef)) {
            await entity.delete();
            cleanedCount++;
          }
        }
      }

      return cleanedCount;
    } catch (e) {
      print('ImageStorageService: Error cleaning orphaned images: $e');
      return 0;
    }
  }
}
