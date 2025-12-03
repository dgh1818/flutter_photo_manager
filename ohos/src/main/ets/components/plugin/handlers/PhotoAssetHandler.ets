import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { HandlerBase, MethodCallHandlerBase } from './HandlerBase';
import PhotoManagerPlugin from '../PhotoManagerPlugin';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodCall } from '@ohos/flutter_ohos';
import { RequestType } from '../types/RequestType';
import { AlbumHandler } from './AlbumHandler';
import { image } from '@kit.ImageKit';
import fs, { ReadOptions, WriteOptions } from '@ohos.file.fs';
import { FilterOption } from '../filter/FilterOption';
import { PermissionHandler } from './PermissionHandler';
import common from '@ohos.app.ability.common';
import util from '@ohos.util';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

import { fileUri, hash } from '@kit.CoreFileKit';
import { fileUriService } from '@kit.ScenarioFusionKit';
import { PMProgressHandler } from './PMProgressHandler';
import { BusinessError } from '@kit.BasicServicesKit';
import { PMProgressState } from './PMProgressHandlerInterface';

export class PhotoAssetHandler extends HandlerBase implements MethodCallHandlerBase {
  async onMethodCall(call: MethodCall, result: MethodResult): Promise<boolean> {
    if (this.uiContext == null) {
      result.error('100', 'uiContext is null', 'it should not be null');
      return true;
    }
    switch (call.method) {
      case 'getAssetListPaged': {
        let args: Map<string, ESObject> = call.args;
        // 'id': id,
        // 'type': type.value,
        // 'page': page,
        // 'size': size,
        // 'option': optionGroup.toMap(),
        // let id: string = args.get('id');
        let page: number = args.get('page');
        let size: number = args.get('size');
        let assets: Array<Map<string, ESObject>> | null = await this.getAssetList(args, page * size, (page + 1) * size);
        if (assets != null) {
          result.success(new Map<string, ESObject>(
            [['data', assets]]
          ));
        }
        else {
          result.error(`${call.method} failed`, `not find assets by ${args}`, null);
        }
      }
        break;
      case 'getFullFile': {
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('id') as string;
        let subtype:number = args.get('subtype') as number
        // 'isOrigin': isOrigin,
        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(id);

        if (!photoAsset)
        {
          result.error(`${call.method} failed`, `not find asset by ${id}`, null);
          return false;
        }

        let photoSubtype = photoAsset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE).valueOf() as number;

        if(photoSubtype==3&&subtype==3) {   //Moving Photo
          // 获取PhotoAsset对应的动态照片对象。
          console.error("enter get moving photo")

          try {
            const uuid = util.generateRandomUUID();
            await photoAccessHelper.MediaAssetManager.requestMovingPhoto(
              this.uiContext,
              photoAsset,
              { deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE },
              {
                // 把回调写成 async，这样内部可以 await requestContent
                onDataPrepared: async (movingPhoto: photoAccessHelper.MovingPhoto) => {
                  try {
                    if (movingPhoto) {
                      if(!fs.accessSync(this.uiContext!.cacheDir + "/movingPhoto")) {
                        fs.mkdirSync(this.uiContext!.cacheDir + "/movingPhoto");
                      }

                      const targetDirectoryPath = this.uiContext!.cacheDir + "/movingPhoto/" + uuid + "/";
                      //console.error(" targetDirectoryPat is " + targetDirectoryPath)
                      let uri = new fileUri.FileUri(id);

                      const inputFilePath = id.substring(id.lastIndexOf("/") + 1);
                      const inputFilePathSplits = inputFilePath.split(".");
                      const outputFileName = inputFilePathSplits[0];
                      let extension: string = ".mp4";
                      let outputFilePath = targetDirectoryPath  + outputFileName + extension;
                      console.error("enter moving photo success:" + outputFilePath);
                      // 等待 movingPhoto 写出视频资源
                      await movingPhoto.requestContent(photoAccessHelper.ResourceType.VIDEO_RESOURCE, outputFilePath);
                      let index = args.get('progressHandler') as number;
                      result.success(outputFilePath);
                    }
                  } catch (err) {
                    result.error("live photo error",err,null)
                  }
                },
                // 可选：处理 onError
              }
            );
          } catch (e) {
            result.error("live photo error",e,null);
            // requestMovingPhoto 本身同步抛错的情况

          }
        } else {
          if (photoAsset != null) {
            let index = args.get('progressHandler') as number;
            if (index!=undefined) {
              let pmProgressHandler = new PMProgressHandler(PhotoManagerPlugin.binding!,index);
              FileUtils.getPathFromUri(this.uiContext, result,photoAsset.uri,undefined,pmProgressHandler);
            } else {
              FileUtils.getPathFromUri(this.uiContext, result,photoAsset.uri);
            }
          }
          else {
            result.error(`${call.method} failed`, `not find asset by ${id}`, null);
          }
        }
      }
        break;
      case 'getOriginBytes': {
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('id');
        //option
        //type
        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(id);
      }
        break;
      case 'getFullFileReadable': {
        let args: Map<string, ESObject> = call.args;
        let name: string = args.get('filename');
        let modifyAt: number = args.get('modifyAt');

        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAssetReadable(name,modifyAt);

        if (photoAsset != null) {
          console.error('photoAsset.uri：' + photoAsset.uri);
          let realPath = FileUtils.getPathFromUri(this.uiContext, result,photoAsset.uri);
        }
        else {
          result.error(`${call.method} failed`, `not find asset by ${name}`, null);
        }
      }
        break;
      case 'getThumb': {
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('id');
        // 'width': size.width,
        // 'height': size.height,
        // 'format': format.index,
        // 'quality': quality,
        // 'frame': frame,
        let option: Map<string, ESObject> = args.get('option');
        let width: number = option.get('width');
        let height: number = option.get('height');
        //option
        //type
        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(id);
        // this.photoAssets.get(id);
        if (photoAsset != null) {

          let pixelMap: image.PixelMap;
          if (width != undefined && height != undefined) {
            pixelMap = await photoAsset.getThumbnail({
              width: width,
              height: height,
            });
          }
          else {
            pixelMap = await photoAsset.getThumbnail({
              width: 600,
              height: 600,
            });
          }
          const imagePackerApi = image.createImagePacker();

          let format: string = 'image/jpeg';
          switch (option.get('format')) {
            case 1:
              format = 'image/png'
              break;
            default:
              break;
          }

          const packOptions: image.PackingOption = {
            format: format,
            quality: option.get('quality'),
          }

          let uint8Array: Uint8Array = new Uint8Array(await imagePackerApi.packing(pixelMap, packOptions));
          pixelMap.release();
          result.success(uint8Array);
        }
        else {
          result.error(`${call.method} failed`, `not find asset by ${args}`, null);
        }
      }
        break;
      case 'getAssetListRange': {
        // 'id': id,
        // 'type': type.value,
        // 'start': start,
        // 'end': end,
        // 'option': optionGroup.toMap(),
        let args: Map<string, ESObject> = call.args;
        let start: number = args.get('start');
        let end: number = args.get('end');

        let assets: Array<Map<string, ESObject>> | null = await this.getAssetList(args, start, end);
        if (assets != null) {
          result.success(new Map<string, ESObject>(
            [['data', assets]]
          ));
        }
        else {
          result.error(`${call.method} failed`, `not find assets by ${args}`, null);
        }
      }
        break;
      case 'getAssetsByRange': {
        // 'type': type.value,
        // 'start': start,
        // 'end': end,
        // 'option': filter.toMap(),
        let args: Map<string, ESObject> = call.args;
        let start: number = args.get('start');
        let end: number = args.get('end');
        let allObjects: Array<photoAccessHelper.Album> = await AlbumHandler.getAlbums(args, true, true);
        let data: Array<Map<string, ESObject>> = [];
        for (let i = 0; i < allObjects.length; i++) {
          const element = allObjects[i];
          if (element.count == 0) {
            continue;
          }
          start = start - element.count;
          end = end = element.count;
          let assets: Array<Map<string, ESObject>> | null = await this.getAssetList(args, start, end, element);
          if (assets != null) {
            data.push(...assets);
          }
          else {
            result.error(`${call.method} failed`, `not find assets by ${args}`, null);
            return true;
          }
        }
        result.success(new Map<string, ESObject>(
          [['data', data]]
        ));
      }
        break;
      case 'deleteWithIds':
      case 'moveToTrash': {
        if (!(await PermissionHandler.permissionWriteCheck())) {
          result.error('no ohos.permission.WRITE_IMAGEVIDEO', '', '');
          return true;
        }
        let args: Map<string, ESObject> = call.args;
        let ids: Array<string> = args.get('ids');


        await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(this.uiContext, ids);
        // 从回收站里面彻底删除，系统接口，目前不支持
        // if (call.method == 'deleteWithIds') {
        //
        // }
        result.success(ids);
      }
        break;
      case 'getColumnNames':
        result.success(Object.keys(photoAccessHelper.PhotoKeys));
        break;
      case 'fetchEntityProperties': {
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('id');
        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(id);
        if (photoAsset != null) {
          result.success(PhotoAssetHandler.photoAssetToMap(photoAsset));
        }
        else {
          result.error(`${call.method} failed`, `not find asset by ${args}`, null);
        }
      }
        break;
      case 'assetExists': {
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('id');
        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(id);
        result.success(photoAsset != null);
      }
        break;
      case 'favoriteAsset': {
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('id');
        let favorite: Boolean = args.get('favorite');
        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(id);
        if (photoAsset == null) {
          result.success(false);
        }
        else {
          result.success(PhotoAssetHandler.setAssetMember(photoAsset, photoAccessHelper.PhotoKeys.FAVORITE, favorite ? 'true' : 'false'));
        }
      }
        break;
      case 'getFileFd': {
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('id');
        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(id);
        if (photoAsset != null) {
          let file = await fs.open(photoAsset.uri, fs.OpenMode.READ_ONLY);
          result.success(file.fd);
        }
        else {
          result.error(`${call.method} failed`, `not find asset by ${args}`, null);
        }
      }
        break;
      case 'copyAsset': {
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('assetId');
        let galleryId: string = args.get('galleryId');
        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(id);

        let album: photoAccessHelper.Album | null = await AlbumHandler.getAlbum(galleryId);
        if (photoAsset != null && album != null) {
          try {
            await AlbumHandler.copyToAlbum(album, photoAsset);
            result.success(PhotoAssetHandler.photoAssetToMap(photoAsset));
          }
          catch (e) {
            result.error(`${call.method} failed`, e.toString(), null);
          }
        }
        else {
          let errorInfo = '';
          if (photoAsset == null) {
            errorInfo = `not find asset by ${id}`;
          }
          if (album == null) {
            errorInfo += `not find album by ${galleryId}`;
          }
          result.error(`${call.method} failed`, errorInfo, null);
        }
      }
        break;
      case 'isLocallyAvailable':
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('id') as string;
        try {
          let islocal = await PhotoAssetHandler.isLocallyAvailable(id);
          result.success(islocal);
        } catch (e) {
          result.error("not found file",e as string,null);
        }
        break;
      default:
        return false;
    }

    return true;
  }

  async getAssetList(args: Map<string, ESObject>, start: number, end: number, album?: photoAccessHelper.AbsAlbum | null): Promise<Array<Map<string, ESObject>> | null> {
    if (!(await PermissionHandler.permissionReadCheck())) {
      return null;
    }
    let id: string = args.get('id');

    album = album ?? await AlbumHandler.getAlbum(id);
    // = this.albums.get(id);
    if (album != undefined) {

      start = Math.max(0, start);
      end = Math.min(end, album.count);
      let assets: Array<Map<string, ESObject>> = [];
      if (start > end) {
        return assets;
      }
      let filterOption: FilterOption = new FilterOption(args.get('option'));
      let requestType: RequestType = new RequestType(args.get('type'));
      let predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
      if (!(requestType.containsImage() && requestType.containsVideo())) {
        if (requestType.containsImage()) {
          predicates.equalTo(photoAccessHelper.PhotoKeys.PHOTO_TYPE, photoAccessHelper.PhotoType.IMAGE);
        }
        else if (requestType.containsVideo()) {
          predicates.equalTo(photoAccessHelper.PhotoKeys.PHOTO_TYPE, photoAccessHelper.PhotoType.VIDEO);
        }
      }

      if (filterOption.child.orderBy.length != 0) {
        for (let index = 0; index < filterOption.child.orderBy.length; index++) {
          const orderByItem = filterOption.child.orderBy[index];
          let column = orderByItem.column;
          if (column.length == 0 || !Object.values(photoAccessHelper.PhotoKeys)
            .includes(column as photoAccessHelper.PhotoKeys)) {
            continue;
          }
          if (orderByItem.isAsc) {
            predicates.orderByAsc(orderByItem.column);
          }
          else {
            predicates.orderByDesc(orderByItem.column);
          }
        }
      }

      if (filterOption.child.orders.length != 0) {
        for (let index = 0; index < filterOption.child.orders.length; index++) {
          const orderItem = filterOption.child.orders[index];
          let column: string | undefined = undefined;
          if (orderItem.type == 0) {
            column = photoAccessHelper.PhotoKeys.DATE_ADDED;
          }
          else if (orderItem.type == 1) {
            column = photoAccessHelper.PhotoKeys.DATE_MODIFIED;
          }
          if (column != undefined) {
            if (orderItem.asc) {
              predicates.orderByAsc(column);
            }
            else {
              predicates.orderByDesc(column);
            }
          }
        }
      }

      let fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: [
          'uri',
          'width',
          'height',
          'duration',
          'orientation',
          'is_favorite',
          'title',
          'date_added',
          'date_modified',
          'media_type',
          'size',
          'position',
          'subtype',
          //...Object.keys(photoAccessHelper.PhotoKeys),
        ],
        predicates: predicates
      };

      let photoFetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> =
        await album.getAssets(fetchOptions);

      for (let index = start; index < end && index < album.count; index++) {
        let photoAsset: photoAccessHelper.PhotoAsset = await photoFetchResult.getObjectByPosition(index);

        let position = photoAsset.get(photoAccessHelper.PhotoKeys.POSITION) as photoAccessHelper.PositionType;
        // if (!(position == photoAccessHelper.PositionType.LOCAL) &&
        //   !(position == photoAccessHelper.PositionType.LOCAL_AND_CLOUD)) {
        //   continue;
        // }

        let fileUriObject = new fileUri.FileUri(photoAsset.uri);
        //console.error('get path success:' + fileUriObject.path);
        assets.push(PhotoAssetHandler.photoAssetToMap(photoAsset));
      }
      photoFetchResult.close();
      return assets;
    }
    else {
      return null;
    }
  }

  static getAssetMember(photoAsset: photoAccessHelper.PhotoAsset, member: string): photoAccessHelper.MemberType | null {
    try {
      return photoAsset.get(member)
    }
    catch (e) {
      return null;
    }
  }

  static setAssetMember(photoAsset: photoAccessHelper.PhotoAsset, member: string, value: string): Boolean {
    try {
      photoAsset.set(member, value);
      return true;
    }
    catch (e) {
      return false;
    }
  }

  static photoAssetToMap(photoAsset: photoAccessHelper.PhotoAsset): Map<string, ESObject> {
    // this.photoAssets.set(photoAsset.uri, photoAsset);
    // typeInt: data['type'] as int,
    // width: data['width'] as int,
    // height: data['height'] as int,
    // duration: data['duration'] as int? ?? 0,
    // orientation: data['orientation'] as int? ?? 0,
    // isFavorite: data['favorite'] as bool? ?? false,
    // title: data['title'] as String? ?? title,
    // subtype: data['subtype'] as int? ?? 0,
    // createDateSecond: data['createDt'] as int?,
    // modifiedDateSecond: data['modifiedDt'] as int?,
    // relativePath: data['relativePath'] as String?,
    // latitude: data['lat'] as double?,
    // longitude: data['lng'] as double?,
    // mimeType: data['mimeType'] as String?,
    let uri = photoAsset.uri;
    // this.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.URI);
    let media_type = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.PHOTO_TYPE) as number;
    let display_name = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.DISPLAY_NAME) as string;
    // let size = this.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.SIZE);
    let date_added = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.DATE_ADDED) as number;
    let date_modified = photoAsset.get(photoAccessHelper.PhotoKeys.DATE_MODIFIED) as number;
    let duration: number = (PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.DURATION) as number) ;
    let width = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.WIDTH) as number;
    let height = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.HEIGHT) as number;
    let orientation = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.ORIENTATION) as number;
    let is_favorite = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.FAVORITE) as number;
    let title = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.DISPLAY_NAME) as string;
    let subtype = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE) as number;

    const displayName = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.DISPLAY_NAME) as string;
    const dot = displayName.lastIndexOf('.');
    const ext = dot >= 0 && dot < displayName.length - 1 ? displayName.substring(dot + 1).toLowerCase() : '';
    const mimeType = media_type == photoAccessHelper.PhotoType.IMAGE
      ? `image/${ext || 'jpeg'}`
      : `video/${ext || 'mp4'}`;
    
    console.error("finish to map");

    return new Map<string, ESObject>(
      [
        ['id', uri],
        // IMAGE 1  VIDEO 2
        ['type', media_type],
        ['width', width],
        ['height', height],
        ['duration', Math.ceil(duration / 1000)],
        ['orientation', orientation],
        ['favorite', is_favorite==1?true:false],
        // dart 会根据 title 获取图片类型，所以这里返回文件路径比较好
        // 鸿蒙的 tilte 不带扩展后缀
        ['title', title],
        // ['subtype', subtype],
        ['createDt', date_added],
        ['modifiedDt', date_modified],
        ['relativePath', uri],
        // latitude: data['lat'] as double?,
        // ['lat', 1.0],
        // longitude: data['lng'] as double?,
        // ['lng', 1.0],
        ['mimeType', mimeType],
        ['subtype', subtype],
      ]
    );
  }


  static async getPhotoAsset(id: string): Promise<photoAccessHelper.PhotoAsset | null> {
    if (!(await PermissionHandler.permissionReadCheck())) {
      return null;
    }
    let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(PhotoManagerPlugin.uiContext);
    let predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, id);
    let fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [
        'uri',
        'width',
        'height',
        'duration',
        'orientation',
        'is_favorite',
        'title',
        'date_added',
        'date_modified',
        'media_type',
        'size',
        'subtype',
        'position',
        //...Object.keys(photoAccessHelper.PhotoKeys),
      ],
      predicates: predicates
    };

    let assets = await phAccessHelper.getAssets(fetchOptions);
    if (assets.getCount() != 0) {
      return await assets.getFirstObject();
    }
    return null;
  }

  static async getPhotoAssetReadable(name: string, modifyAt : number): Promise<photoAccessHelper.PhotoAsset | null> {
    if (!(await PermissionHandler.permissionReadCheck())) {
      return null;
    }
    let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(PhotoManagerPlugin.uiContext);
    let predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
    // predicates.equalTo(photoAccessHelper.PhotoKeys.PositionType, photoAccessHelper.PositionType.LOCAL);
    // predicates.equalTo(photoAccessHelper.PhotoKeys.PositionType, photoAccessHelper.PositionType.LOCAL_AND_CLOUD);
    predicates.equalTo(photoAccessHelper.PhotoKeys.DISPLAY_NAME, name);
    // .and()
    // .equalTo(photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS, modifyAt);

    //TODO:恢复比较时间
    let fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [
        'width',
        'height',
        'duration',
        'orientation',
        'is_favorite',
        'title',
        'date_added',
        'date_modified',
        'media_type',
        'size',
        //...Object.keys(photoAccessHelper.PhotoKeys),
      ],
      predicates: predicates
    };

    let assets = await phAccessHelper.getAssets(fetchOptions);
    if (assets.getCount() != 0) {

      return await assets.getFirstObject();

      // if(asset.PositionType == PositionType.LOCAL || asset.PositionType == PositionType.LOCAL_AND_CLOUD)
      // return asset;
    }
    return null;

  }

  static async isLocallyAvailable(id:string):Promise<Boolean> {
    if (!(await PermissionHandler.permissionReadCheck())) {
      return false;
    }
    let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(PhotoManagerPlugin.uiContext);
    let predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, id);
    let fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [
        'uri',
        'width',
        'height',
        'duration',
        'orientation',
        'is_favorite',
        'title',
        'date_added',
        'date_modified',
        'media_type',
        'size',
        'position',
        'subtype',
        //...Object.keys(photoAccessHelper.PhotoKeys),
      ],
      predicates: predicates
    };

    let assets = await phAccessHelper.getAssets(fetchOptions);
    if (assets.getCount() == 0) {
      return false;
    }

    let asset = await assets.getFirstObject();

    let position = asset.get(photoAccessHelper.PhotoKeys.POSITION) as photoAccessHelper.PositionType;
    if (!(position == photoAccessHelper.PositionType.LOCAL) &&
      !(position == photoAccessHelper.PositionType.LOCAL_AND_CLOUD)) {
      return false;
    } else {
      return true;
    }

  }
}

const TAG = "FileUtils";

class FileUtils {
  static async getPathFromUri(context: common.Context | null, result:MethodResult,uri: string, defExtension?: string, pmProgressHandler?:PMProgressHandler) {
    Log.i(TAG, "getPathFromUri : " + uri);
    const uuid = util.generateRandomUUID();
    if (!context) {
      return
    }
    {
      if(!fs.accessSync(context.cacheDir + "/originalPhoto")) {
        fs.mkdirSync(context.cacheDir + "/originalPhoto");
      }
      const targetDirectoryPath = context.cacheDir + "/originalPhoto/" + uuid;
      try {
        fs.mkdirSync(targetDirectoryPath);
        let targetDir = fs.openSync(targetDirectoryPath);
        Log.i(TAG, "mkdirSync success targetDirectoryPath:" + targetDirectoryPath + " fd: " + targetDir.fd);
        fs.closeSync(targetDir);
      } catch (err) {
        Log.e(TAG, "mkdirSync failed err:" + err);
        return null;
      }

      const inputFilePath = uri.substring(uri.lastIndexOf("/") + 1);
      const inputFilePathSplits = inputFilePath.split(".");
      Log.i(TAG, "getPathFromUri inputFilePath: " + inputFilePath);
      const outputFileName = inputFilePathSplits[0];
      let extension: string;
      if (inputFilePathSplits.length == 2) {
        extension = "." + inputFilePathSplits[1];
      } else {
        if (defExtension) {
          extension = defExtension;
        } else {
          extension = ".jpg";
        }
      }
      const outputFilePath = targetDirectoryPath + "/" + outputFileName + extension;

      try {
        let progressListener: fs.ProgressListener = (progress: fs.Progress) => {
          console.info(`progressSize: ${progress.processedSize}, totalSize: ${progress.totalSize}`);
          pmProgressHandler?.notify(progress.processedSize/progress.totalSize,PMProgressState.Loading);
        };
        let copyOption: fs.CopyOptions = {
          "progressListener" : progressListener
        }
        let dstDirUriLocal: string = fileUri.getUriFromPath(outputFilePath);

        fs.copy(uri, dstDirUriLocal, copyOption, (err: BusinessError) => {
          if (err) {
            console.error(`Failed to copy. Code: ${err.code}, message: ${err.message}`);
            pmProgressHandler?.notify(0.0,PMProgressState.Failed);
            result.error("copy file error",inputFilePath,null);
            return;
          }
          console.info("Succeeded in copying.");
          pmProgressHandler?.notify(100.0,PMProgressState.Success);
          let filepath =
            result.success(outputFilePath);
        })
      } catch (err) {
        console.error(TAG, "copyFile failed err:" + err);
        result.error("copy file error",inputFilePath,null);
        return null;
      } finally {
        //fs.closeSync(inputFile);
        //fs.closeSync(outputFile);
      }
      return outputFilePath;
    }
  }
}
