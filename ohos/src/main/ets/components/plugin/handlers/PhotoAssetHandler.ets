import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { HandlerBase, MethodCallHandlerBase } from './HandlerBase';
import PhotoManagerPlugin from '../PhotoManagerPlugin';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { RequestType } from '../types/RequestType';
import { AlbumHandler } from './AlbumHandler';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { FilterOption } from '../filter/FilterOption';
import { PermissionHandler } from './PermissionHandler';
import common from '@ohos.app.ability.common';
import util from '@ohos.util';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

import { fileUri } from '@kit.CoreFileKit';
import { PMProgressHandler } from './PMProgressHandler';
import { BusinessError } from '@kit.BasicServicesKit';
import { PMProgressState } from './PMProgressHandlerInterface';

export class PhotoAssetHandler extends HandlerBase implements MethodCallHandlerBase {
  async onMethodCall(call: MethodCall, result: MethodResult): Promise<boolean> {
    if (this.context == null) {
      result.error('100', 'context is null', 'it should not be null');
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
        } else {
          result.error(`${call.method} failed`, `not find assets by ${args}`, null);
        }
      }
        break;
      case 'getFullFile': {
        let args: Map<string, ESObject> = call.args;
        let id: string = args.get('id') as string;
        let isOrigin: boolean = args.get('isOrigin') as boolean;
        let subtype: number = args.get('subtype') as number;
        let pmProgressHandler: PMProgressHandler | undefined = undefined;
        let index = args.get('progressHandler') as number;
        if (index != undefined) {
          console.error("getFullFile with progressHandler:" + index);
          pmProgressHandler = new PMProgressHandler(PhotoManagerPlugin.binding!, index);
        }

        await FileUtils.getFullSizeFileWithId(this.context, result, id, isOrigin, subtype, pmProgressHandler);
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
        let resizeContentMode: number = option.get('resizeContentMode') as number;
        //option
        //type
        let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(id);
        // this.photoAssets.get(id);
        if (photoAsset != null) {
          const thumbnailSize = PhotoAssetHandler.makeThumbnailRequestSize(
            photoAsset,
            width,
            height,
            resizeContentMode,
          );
          let pixelMap: image.PixelMap = await photoAsset.getThumbnail(thumbnailSize);
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
        } else {
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
        } else {
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
          } else {
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

        // deleteAssets 单次最多 300 个资产，超出直接拒绝，需分批调用
        const maxDeleteCount = 300;
        for (let i = 0; i < ids.length; i += maxDeleteCount) {
          const chunk: Array<string> = ids.slice(i, Math.min(i + maxDeleteCount, ids.length));
          try {
            await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(this.context!, chunk);
          } catch (e) {
            const error = e as BusinessError;
            if (error.code === 201 && (error.message ?? '').toLowerCase().includes('user deny')) {
              result.success(ids.slice(0, i));
            } else {
              result.error(`${error.code}`, call.method, `${error.message}`);
            }
            return true;
          }
        }
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
        } else {
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
        } else {
          result.success(PhotoAssetHandler.setAssetMember(photoAsset, photoAccessHelper.PhotoKeys.FAVORITE,
            favorite ? 'true' : 'false'));
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
        } else {
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
          } catch (e) {
            result.error(`${call.method} failed`, e.toString(), null);
          }
        } else {
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
          result.error("not found file", e as string, null);
        }
        break;
      default:
        return false;
    }

    return true;
  }

  async getAssetList(args: Map<string, ESObject>, start: number, end: number,
    album?: photoAccessHelper.AbsAlbum | null): Promise<Array<Map<string, ESObject>> | null> {
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
        } else if (requestType.containsVideo()) {
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
          } else {
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
          } else if (orderItem.type == 1) {
            column = photoAccessHelper.PhotoKeys.DATE_MODIFIED;
          }
          if (column != undefined) {
            if (orderItem.asc) {
              predicates.orderByAsc(column);
            } else {
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
    } else {
      return null;
    }
  }

  static getAssetMember(photoAsset: photoAccessHelper.PhotoAsset, member: string): photoAccessHelper.MemberType | null {
    try {
      return photoAsset.get(member)
    } catch (e) {
      return null;
    }
  }

  static setAssetMember(photoAsset: photoAccessHelper.PhotoAsset, member: string, value: string): Boolean {
    try {
      photoAsset.set(member, value);
      return true;
    } catch (e) {
      return false;
    }
  }

  private static getOrientedAssetSize(photoAsset: photoAccessHelper.PhotoAsset): Size {
    const width = (PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.WIDTH) as number) || 1;
    const height = (PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.HEIGHT) as number) || 1;
    const orientation =
      (PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.ORIENTATION) as number) || 0;
    if (orientation == 90 || orientation == 270) {
      return { width: height, height: width };
    }
    return { width: width, height: height };
  }

  private static makeAspectFitThumbnailSize(
    requestWidth: number,
    requestHeight: number,
    photoAsset: photoAccessHelper.PhotoAsset,
  ): Size {
    const orientedSize = PhotoAssetHandler.getOrientedAssetSize(photoAsset);
    let boundWidth = requestWidth != undefined && requestWidth > 0 ? requestWidth : 0;
    let boundHeight = requestHeight != undefined && requestHeight > 0 ? requestHeight : 0;

    if (boundWidth <= 0 && boundHeight <= 0) {
      boundWidth = 600;
      boundHeight = 600;
    } else if (boundWidth <= 0) {
      boundWidth = Math.round(boundHeight * orientedSize.width / orientedSize.height);
    } else if (boundHeight <= 0) {
      boundHeight = Math.round(boundWidth * orientedSize.height / orientedSize.width);
    }

    const scale = Math.min(boundWidth / orientedSize.width, boundHeight / orientedSize.height);
    const width = Math.max(1, Math.round(orientedSize.width * scale));
    const height = Math.max(1, Math.round(orientedSize.height * scale));
    return { width: width, height: height };
  }

  private static makeThumbnailRequestSize(
    photoAsset: photoAccessHelper.PhotoAsset,
    requestWidth: number,
    requestHeight: number,
    resizeContentMode: number,
  ): Size {
    if (resizeContentMode == 1) {
      const orientedSize = PhotoAssetHandler.getOrientedAssetSize(photoAsset);
      let width = requestWidth != undefined && requestWidth > 0 ? requestWidth : orientedSize.width;
      let height = requestHeight != undefined && requestHeight > 0 ? requestHeight : orientedSize.height;
      if (width <= 0) {
        width = 600;
      }
      if (height <= 0) {
        height = 600;
      }
      return { width: width, height: height };
    }

    // OHOS getThumbnail has no content-mode parameter, so default to the iOS behavior (AspectFit)
    // by fitting the request bounds against the asset's oriented dimensions.
    return PhotoAssetHandler.makeAspectFitThumbnailSize(requestWidth, requestHeight, photoAsset);
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
    let duration: number =
      (PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.DURATION) as number);
    let width = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.WIDTH) as number;
    let height = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.HEIGHT) as number;
    let orientation = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.ORIENTATION) as number;
    let is_favorite = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.FAVORITE) as number;
    let title = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.DISPLAY_NAME) as string;
    let subtype = PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE) as number;

    const displayName =
      PhotoAssetHandler.getAssetMember(photoAsset, photoAccessHelper.PhotoKeys.DISPLAY_NAME) as string;
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
        ['favorite', is_favorite == 1 ? true : false],
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
      console.error("no read permission");
      return null;
    }
    const context = PhotoManagerPlugin.uiContext ?? PhotoManagerPlugin.context;
    if (!context) {
      return null;
    }
    let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
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

  static async isLocallyAvailable(id: string): Promise<Boolean> {
    if (!(await PermissionHandler.permissionReadCheck())) {
      return false;
    }
    const context = PhotoManagerPlugin.uiContext ?? PhotoManagerPlugin.context;
    if (!context) {
      return false;
    }
    let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
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
    if (position == photoAccessHelper.PositionType.CLOUD) {
      return false;
    } else {
      return true;
    }

  }
}

const TAG = "FileUtils";

class FileUtils {
  static async getFullSizeFileWithId(context: common.Context | null, result: MethodResult, assetId: string,
    isOrigin: boolean, subtype: number, pmProgressHandler?: PMProgressHandler): Promise<void> {
    let photoAsset: photoAccessHelper.PhotoAsset | null = await PhotoAssetHandler.getPhotoAsset(assetId);
    if (!photoAsset) {
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("getFullFile failed", `not find asset by ${assetId}`, null);
      return;
    }

    let photoSubtype = photoAsset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE).valueOf() as number;
    if (photoSubtype == 3 && subtype == 3) {
      await FileUtils.fetchLivePhotosFile(context, result, photoAsset, pmProgressHandler);
      return;
    }

    if (isOrigin) {
      await FileUtils.fetchOriginAssetFile(context, result, photoAsset, pmProgressHandler);
    } else {
      await FileUtils.fetchFullSizeAssetFile(context, result, photoAsset, pmProgressHandler);
    }
  }

  static createRequestOptions(pmProgressHandler?: PMProgressHandler,
    compatibleMode?: photoAccessHelper.CompatibleMode): photoAccessHelper.RequestOptions {
    let requestOptions: photoAccessHelper.RequestOptions = {
      deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE
    };
    if (compatibleMode != undefined) {
      requestOptions.compatibleMode = compatibleMode;
    }
    if (pmProgressHandler) {
      requestOptions.mediaAssetProgressHandler = {
        onProgress: (progress: number) => {
          const normalized = Math.max(0, Math.min(progress, 100)) / 100;
          pmProgressHandler.notify(normalized, PMProgressState.Loading);
        }
      };
    }
    return requestOptions;
  }

  static getPhotoType(photoAsset: photoAccessHelper.PhotoAsset): number {
    return photoAsset.get(photoAccessHelper.PhotoKeys.PHOTO_TYPE).valueOf() as number;
  }

  static getErrorMessage(error: BusinessError | Error, fallback: string): string {
    if (error.message) {
      return error.message;
    }
    return fallback;
  }

  static async fetchLivePhotosFile(context: common.Context | null, result: MethodResult,
    photoAsset: photoAccessHelper.PhotoAsset, pmProgressHandler?: PMProgressHandler): Promise<void> {
    if (!context) {
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("getFullFile failed", "context is null", null);
      return;
    }

    const outputFilePath = FileUtils.makeAssetOutputPath("movingPhoto", photoAsset.uri, ".mp4", false);
    if (!outputFilePath) {
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("cache dir error", "cache root is null", null);
      return;
    }

    pmProgressHandler?.notify(0.0, PMProgressState.Prepare);
    try {
      await photoAccessHelper.MediaAssetManager.requestMovingPhoto(
        context,
        photoAsset,
        { deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE },
        {
          onDataPrepared: async (movingPhoto: photoAccessHelper.MovingPhoto) => {
            if (!movingPhoto) {
              pmProgressHandler?.notify(0.0, PMProgressState.Failed);
              result.error("live photo error", "moving photo is null", null);
              return;
            }

            try {
              await movingPhoto.requestContent(photoAccessHelper.ResourceType.VIDEO_RESOURCE, outputFilePath);
              pmProgressHandler?.notify(1.0, PMProgressState.Success);
              result.success(outputFilePath);
            } catch (e) {
              let error = e as BusinessError;
              console.error("requestContent video error: " + error.message);
              pmProgressHandler?.notify(0.0, PMProgressState.Failed);
              result.error("live photo error", error.message, null);
            }
          },
        }
      );
    } catch (e) {
      let error = e as BusinessError;
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("live photo error", error.message, null);
    }
  }

  static async fetchOriginAssetFile(context: common.Context | null, result: MethodResult,
    photoAsset: photoAccessHelper.PhotoAsset, pmProgressHandler?: PMProgressHandler): Promise<void> {
    if (FileUtils.getPhotoType(photoAsset) == photoAccessHelper.PhotoType.VIDEO) {
      await FileUtils.fetchOriginVideoFile(context, result, photoAsset, pmProgressHandler);
      return;
    }
    await FileUtils.fetchOriginImageFile(context, result, photoAsset, pmProgressHandler);
  }

  static async fetchFullSizeAssetFile(context: common.Context | null, result: MethodResult,
    photoAsset: photoAccessHelper.PhotoAsset, pmProgressHandler?: PMProgressHandler): Promise<void> {
    if (FileUtils.getPhotoType(photoAsset) == photoAccessHelper.PhotoType.VIDEO) {
      await FileUtils.fetchFullSizeVideo(context, result, photoAsset, pmProgressHandler);
      return;
    }
    await FileUtils.fetchFullSizeImageFile(context, result, photoAsset, pmProgressHandler);
  }

  static async fetchOriginImageFile(context: common.Context | null, result: MethodResult,
    photoAsset: photoAccessHelper.PhotoAsset, pmProgressHandler?: PMProgressHandler): Promise<void> {
    await FileUtils.copyAssetToCache(context, result, photoAsset.uri, "originalPhoto", undefined, pmProgressHandler);
  }

  static async fetchFullSizeImageFile(context: common.Context | null, result: MethodResult,
    photoAsset: photoAccessHelper.PhotoAsset, pmProgressHandler?: PMProgressHandler): Promise<void> {
    if (!context) {
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("getFullFile failed", "context is null", null);
      return;
    }

    const outputFilePath = FileUtils.makeAssetOutputPath("fullPhoto", photoAsset.uri, ".jpg", false);
    if (!outputFilePath) {
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("full photo error", "cache root is null", null);
      return;
    }

    pmProgressHandler?.notify(0.0, PMProgressState.Prepare);
    try {
      await new Promise<void>(async (resolve, reject) => {
        let settled = false;
        const resolveOnce = () => {
          if (settled) {
            return;
          }
          settled = true;
          resolve();
        };
        const rejectOnce = (error: BusinessError | Error) => {
          if (settled) {
            return;
          }
          settled = true;
          reject(error);
        };

        try {
          await photoAccessHelper.MediaAssetManager.requestImage(
            context,
            photoAsset,
            FileUtils.createRequestOptions(pmProgressHandler),
            {
              onDataPrepared: async (imageSource: image.ImageSource) => {
                try {
                  await FileUtils.writeFullFileWithAssetId(imageSource, outputFilePath);
                  resolveOnce();
                } catch (error) {
                  rejectOnce(error as BusinessError | Error);
                } finally {
                  try {
                    await imageSource.release();
                  } catch (_) {
                  }
                }
              }
            }
          );
        } catch (error) {
          rejectOnce(error as BusinessError | Error);
        }
      });
      pmProgressHandler?.notify(1.0, PMProgressState.Success);
      result.success(outputFilePath);
    } catch (error) {
      const message = FileUtils.getErrorMessage(error as BusinessError | Error, "requestImage failed");
      console.error("requestImage error: " + message);
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("full photo error", message, null);
    }
  }

  static async fetchOriginVideoFile(context: common.Context | null, result: MethodResult,
    photoAsset: photoAccessHelper.PhotoAsset, pmProgressHandler?: PMProgressHandler): Promise<void> {
    await FileUtils.copyAssetToCache(context, result, photoAsset.uri, "originalVideo", undefined, pmProgressHandler);
  }

  static async fetchFullSizeVideo(context: common.Context | null, result: MethodResult,
    photoAsset: photoAccessHelper.PhotoAsset, pmProgressHandler?: PMProgressHandler): Promise<void> {
    if (!context) {
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("getFullFile failed", "context is null", null);
      return;
    }

    const outputFilePath = FileUtils.makeAssetOutputPath("fullVideo", photoAsset.uri, ".mp4");
    if (!outputFilePath) {
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("full video error", "cache root is null", null);
      return;
    }

    pmProgressHandler?.notify(0.0, PMProgressState.Prepare);
    try {
      await FileUtils.fetchVideoResourceToFile(context, photoAsset, outputFilePath, pmProgressHandler);
      pmProgressHandler?.notify(1.0, PMProgressState.Success);
      result.success(outputFilePath);
    } catch (error) {
      const message = FileUtils.getErrorMessage(error as BusinessError | Error, "requestVideoFile failed");
      console.error("requestVideoFile error: " + message);
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("full video error", message, null);
    }
  }

  static async fetchVideoResourceToFile(context: common.Context, photoAsset: photoAccessHelper.PhotoAsset,
    outputFilePath: string, pmProgressHandler?: PMProgressHandler): Promise<void> {
    const outputFileUri = fileUri.getUriFromPath(outputFilePath);
    await new Promise<void>(async (resolve, reject) => {
      let settled = false;
      const resolveOnce = () => {
        if (settled) {
          return;
        }
        settled = true;
        resolve();
      };
      const rejectOnce = (error: BusinessError | Error) => {
        if (settled) {
          return;
        }
        settled = true;
        reject(error);
      };

      try {
        await photoAccessHelper.MediaAssetManager.requestVideoFile(
          context,
          photoAsset,
          FileUtils.createRequestOptions(pmProgressHandler, photoAccessHelper.CompatibleMode.ORIGINAL_FORMAT_MODE),
          outputFileUri,
          {
            onDataPrepared: (isPrepared: boolean) => {
              if (!isPrepared) {
                rejectOnce(new Error("video data not prepared"));
                return;
              }
              resolveOnce();
            }
          }
        );
      } catch (error) {
        rejectOnce(error as BusinessError | Error);
      }
    });
  }

  static async writeFullFileWithAssetId(imageSource: image.ImageSource, outputFilePath: string): Promise<void> {
    const outputFile = fs.openSync(outputFilePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    const imagePacker = image.createImagePacker();
    try {
      await imagePacker.packToFile(imageSource, outputFile.fd, {
        format: "image/jpeg",
        quality: 100
      });
    } finally {
      try {
        fs.closeSync(outputFile);
      } catch (_) {
      }
      try {
        await imagePacker.release();
      } catch (_) {
      }
    }
  }

  static async copyAssetToCache(context: common.Context | null, result: MethodResult, uri: string,
    cacheDirectory: string, defExtension?: string, pmProgressHandler?: PMProgressHandler): Promise<string | null> {
    Log.i(TAG, "copyAssetToCache : " + uri);
    if (!context) {
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("copy file error", "context is null", null);
      return null;
    }

    const inputFilePath = uri.substring(uri.lastIndexOf("/") + 1);
    const outputFilePath = FileUtils.makeAssetOutputPath(cacheDirectory, uri, defExtension);
    if (!outputFilePath) {
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("copy file error", "cache root is null", null);
      return null;
    }

    pmProgressHandler?.notify(0.0, PMProgressState.Prepare);
    try {
      let progressListener: fs.ProgressListener = (progress: fs.Progress) => {
        const totalSize = progress.totalSize > 0 ? progress.totalSize : 1;
        pmProgressHandler?.notify(progress.processedSize / totalSize, PMProgressState.Loading);
      };
      let copyOption: fs.CopyOptions = {
        "progressListener": progressListener
      }
      let dstDirUriLocal: string = fileUri.getUriFromPath(outputFilePath);
      console.error(TAG, `copyFile from ${uri} to ${dstDirUriLocal}`);
      await new Promise<void>((resolve, reject) => {
        fs.copy(uri, dstDirUriLocal, copyOption, (err: BusinessError) => {
          if (err) {
            reject(err);
            return;
          }
          resolve();
        })
      });
      console.info("Succeeded in copying.");
      pmProgressHandler?.notify(1.0, PMProgressState.Success);
      result.success(outputFilePath);
    } catch (err) {
      const businessError = err as BusinessError;
      console.error(TAG, `copyFile failed err:${businessError.code} ${businessError.message}`);
      pmProgressHandler?.notify(0.0, PMProgressState.Failed);
      result.error("copy file error", inputFilePath, null);
      return null;
    }
    return outputFilePath;
  }

  static makeAssetOutputPath(cacheDirectory: string, uri: string,
    defExtension?: string, preferInputExtension: boolean = true): string | null {
    const appContext = PhotoManagerPlugin.uiContext?.getApplicationContext() ?? PhotoManagerPlugin.context;
    if (!appContext) {
      return null;
    }

    const cacheRoot = `${appContext.cacheDir}/photo_manager`;
    if (!fs.accessSync(cacheRoot)) {
      fs.mkdirSync(cacheRoot);
    }
    const targetRoot = `${cacheRoot}/${cacheDirectory}`;
    if (!fs.accessSync(targetRoot)) {
      fs.mkdirSync(targetRoot);
    }

    const uuid = util.generateRandomUUID();
    const targetDirectoryPath = `${targetRoot}/${uuid}`;
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
    const extensionIndex = inputFilePath.lastIndexOf(".");
    const hasInputExtension = extensionIndex > 0 && extensionIndex < inputFilePath.length - 1;
    const outputFileName = hasInputExtension ? inputFilePath.substring(0, extensionIndex) : inputFilePath;
    let extension: string;
    if (preferInputExtension && hasInputExtension) {
      extension = inputFilePath.substring(extensionIndex);
    } else if (defExtension) {
      extension = defExtension;
    } else if (hasInputExtension) {
      extension = inputFilePath.substring(extensionIndex);
    } else {
      extension = ".jpg";
    }

    return `${targetDirectoryPath}/${outputFileName}${extension}`;
  }
}
