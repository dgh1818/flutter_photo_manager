import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { PhotoAssetHandler } from './PhotoAssetHandler';
import { MethodCall } from '@ohos/flutter_ohos';
import { HandlerBase, MethodCallHandlerBase } from './HandlerBase';
import { PermissionHandler } from './PermissionHandler';
import PhotoManagerPlugin from '../PhotoManagerPlugin';
import { AlbumHandler } from './AlbumHandler';

export class SaveHandler extends HandlerBase implements MethodCallHandlerBase {
  async onMethodCall(call: MethodCall, result: MethodResult): Promise<boolean> {
    if (this.context == null) {
      result.error('100', `${call.method} : context is null`, 'it should not be null');
      return true;
    }
    switch (call.method) {
      case 'saveImage': {
        // 'image': data,
        // 'title': title,
        // 'desc': desc ?? '',
        // 'relativePath': relativePath,
        // 'onlyAddPermission': true,
        let args: Map<string, ESObject> = call.args;
        let list: Uint8Array = args.get('image');
        await this._save(args, result, photoAccessHelper.PhotoType.IMAGE, list.buffer as ArrayBuffer);
      }
        break;
      case 'saveImageWithPath': {
        // 'path': path,
        // 'title': title,
        // 'desc': desc ?? '',
        // 'relativePath': relativePath,
        // 'onlyAddPermission': true,
        let args: Map<string, ESObject> = call.args;
        let path: string = args.get('path');
        let buff = await SaveHandler.getBuffFromPath(path);
        await this._save(args, result, photoAccessHelper.PhotoType.IMAGE, buff);
      }
        break;
      case 'saveVideo': {
        // 'path': path,
        // 'title': title,
        // 'desc': desc ?? '',
        // 'relativePath': relativePath,
        // 'onlyAddPermission': true,
        let args: Map<string, ESObject> = call.args;
        let path: string = args.get('path');
        if (!(await PermissionHandler.permissionWriteCheck())) {
          result.error('no ohos.permission.WRITE_IMAGEVIDEO', '', '');
        }

        let title: string = args.get('title');
        let extension: string = 'mp4';
        if (title != undefined && title.includes('.')) {
          const lastIndex = title.lastIndexOf('.');
          if (lastIndex > 0 && lastIndex < title.length -1) {
            extension = title.slice(lastIndex + 1);
            title = title.slice(0, lastIndex);
          }
        }

        try {
          let createOptions: photoAccessHelper.CreateOptions = {};
          if (title != undefined) {
            createOptions = {
              title: title,
            };
          }
          let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context!);
          let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
            photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(this.context!, photoAccessHelper.PhotoType.VIDEO, extension, createOptions);
          assetChangeRequest.addResource(photoAccessHelper.ResourceType.VIDEO_RESOURCE, path);
          await phAccessHelper.applyChanges(assetChangeRequest);
          let asset = assetChangeRequest.getAsset();
          let assetUri = asset.uri;
          let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(assetUri);
          if (photoAsset != null) {
            result.success(PhotoAssetHandler.photoAssetToMap(photoAsset));
          } else {
            if (PhotoManagerPlugin.showLog) {
              console.info('can not find photo for now', assetUri, '');
            }
            result.error('can not find photo for now', assetUri, '');
          }
        } catch (error) {
          let err: BusinessError = error as BusinessError;
          console.error(`save failed: title=${title}, ext=${extension}, type=${photoAccessHelper.PhotoType.VIDEO}`);
          if (PhotoManagerPlugin.showLog) {
            console.info(err.code.toString(), err.message, err.stack);
          }
          result.error(err.code.toString(), err.message, err.stack);
        }
      }
        break;
      case 'saveLivePhoto': {
        let args: Map<string, ESObject> = call.args;
        let imagePath = args.get('imagePath') as string;
        let videoPath = args.get('videoPath') as string;
        let title = args.get("title") as string;
        let desc = args.get("desc") as string;
        let relativePath = args.get("relativePath") as string;
        console.error(`[photo_manager][saveLivePhoto] request, imagePath=${imagePath}, videoPath=${videoPath}, title=${title}, desc=${desc}, relativePath=${relativePath}`);

        try {
          let asset = await AlbumHandler.saveLivePhoto(imagePath, videoPath, title, desc);
          if (asset == undefined) {
            const message = 'AlbumHandler.saveLivePhoto returned undefined';
            console.error(`[photo_manager][saveLivePhoto] failed at handler boundary, imagePath=${imagePath}, videoPath=${videoPath}, message=${message}`);
            result.error('saveLivePhoto failed', message, `imagePath=${imagePath}; videoPath=${videoPath}`);
            return true;
          }
          console.error(`[photo_manager][saveLivePhoto] success, uri=${asset.uri}, imagePath=${imagePath}, videoPath=${videoPath}`);
          let uri = asset.uri as string;
          let media_type = PhotoAssetHandler.getAssetMember(asset, photoAccessHelper.PhotoKeys.PHOTO_TYPE) as number;
          let subtype = 3;
          result.success(new Map<string, ESObject>(
            [
              ['id', uri],
              // IMAGE 1  VIDEO 2
              ['type', media_type],
              ['width', 0],
              ['height', 0],
              ['title', title],
              ['subtype', subtype],
            ]
          ));
        } catch (error) {
          let err = error as BusinessError;
          const code = err.code != undefined ? err.code.toString() : 'saveLivePhoto failed';
          const message = err.message != undefined ? err.message : 'unknown error';
          const details = err.stack != undefined
            ? `${err.stack}; imagePath=${imagePath}; videoPath=${videoPath}`
            : `imagePath=${imagePath}; videoPath=${videoPath}`;
          console.error(`[photo_manager][saveLivePhoto] method failed, code=${code}, message=${message}, details=${details}`);
          result.error(code, message, details);
        }
        return true;

        break;

      }
      default:
        return false;
    }

    return true;
  }


  private static async getBuffFromPath(path: string): Promise<ArrayBuffer> {
    let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    let stat = await fs.stat(file.fd);
    let buff = new ArrayBuffer(stat.size);
    await fs.read(file.fd, buff);
    fs.close(file.fd);
    return buff;
  }

  private async _save(args: Map<string, ESObject>, result: MethodResult, photoType: photoAccessHelper.PhotoType, buffer: ArrayBuffer,
    //  srcUri?: string
  ): Promise<void> {
    if (!(await PermissionHandler.permissionWriteCheck())) {
      result.error('no ohos.permission.WRITE_IMAGEVIDEO', '', '');
    }

    let title: string = args.get('title');
    let extension: string = photoType == photoAccessHelper.PhotoType.IMAGE ? 'jpg' : 'mp4';
    if (title != undefined && title.includes('.')) {
      const lastIndex = title.lastIndexOf('.');
      if (lastIndex > 0 && lastIndex < title.length -1) {
        extension = title.slice(lastIndex + 1);
        title = title.slice(0, lastIndex);
      }
    }

    try {
      let createOptions: photoAccessHelper.CreateOptions = {};
      if (title != undefined) {
        createOptions = {
          title: title,
        };
      }
      let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context!);
      let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(this.context!, photoType, extension, createOptions);
      assetChangeRequest.addResource(photoType == photoAccessHelper.PhotoType.IMAGE ? photoAccessHelper.ResourceType.IMAGE_RESOURCE : photoAccessHelper.ResourceType.VIDEO_RESOURCE, buffer);
      await phAccessHelper.applyChanges(assetChangeRequest);
      let asset = assetChangeRequest.getAsset();
      let path = asset.uri;
      let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(path);
      if (photoAsset != null) {
        result.success(PhotoAssetHandler.photoAssetToMap(photoAsset));
      }
      else {
        if (PhotoManagerPlugin.showLog) {
          console.info('can not find photo for now', path, '');
        }
        result.error('can not find photo for now', path, '');
      }
    } catch (error) {
      let err: BusinessError = error as BusinessError;
      console.error(`save failed: title=${title}, ext=${extension}, type=${photoType}`);
      if (PhotoManagerPlugin.showLog) {
        
        console.info(err.code.toString(), err.message, err.stack);
      }
      result.error(err.code.toString(), err.message, err.stack);
    }
  }

}
