import { AbilityAware, AbilityPluginBinding, FlutterPlugin, MethodCall } from '@ohos/flutter_ohos';
import { FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { EnumUtils } from './utils/EnumUtils';
import { HashMap } from '@kit.ArkTS';
import { MethodCallHandlerBase } from './handlers/HandlerBase';
import PhotoManagerPlugin from './PhotoManagerPlugin';
import util from '@ohos.util';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import fs from '@ohos.file.fs';

export default class PhotoManagerNotifyPlugin implements FlutterPlugin, MethodCallHandlerBase, AbilityAware {
  private static channel: MethodChannel | null = null;
  // private context: Context | null = null;
  private uiContext: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return 'PhotoManagerNotifyPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    PhotoManagerNotifyPlugin.channel = new MethodChannel(binding.getBinaryMessenger(), "com.fluttercandies/photo_manager/notify");
    PhotoManagerNotifyPlugin.channel.setMethodCallHandler(this)
    // this.context = binding.getApplicationContext();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (PhotoManagerNotifyPlugin.channel != null) {
      PhotoManagerNotifyPlugin.channel.setMethodCallHandler(null)
    }
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.uiContext = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {

  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<boolean> {
    switch (call.method) {
      case 'notify': {
        let args: Map<string, ESObject> = call.args;
        let notify: boolean = args.get('notify');
        result.success(this.notify(notify));
      }
        break;
      default:
        return false;
    }
    return true;
  }

  notify(start: boolean): boolean {
    let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.uiContext);
    try {
      if (start) {
        phAccessHelper.registerChange(photoAccessHelper.DefaultChangeUri.DEFAULT_PHOTO_URI, true, this._onCallback);
      }
      else {
        phAccessHelper.unRegisterChange(photoAccessHelper.DefaultChangeUri.DEFAULT_PHOTO_URI, this._onCallback);
      }
      return true;
    }
    catch (e) {
    }
    return false;
  }

  _onCallback(changeData: photoAccessHelper.ChangeData) {
    if (PhotoManagerPlugin.showLog) {
      console.info('onCallback successfully, changData: ' + JSON.stringify(changeData));
    }

    let map: HashMap<string, ESObject> = new  HashMap<string, ESObject>();
    if (changeData.type != undefined) {
      // let keys = Object.keys(photoAccessHelper.NotifyType)
      //   .filter(x => (photoAccessHelper.NotifyType[x] === changeData.type));
      let typeName: string = EnumUtils.getName(photoAccessHelper.NotifyType, changeData.type);
      map.set('type', changeData.type);
      map.set('typeName', typeName.toLowerCase());
    }

    let realPath:Array<string> = [];
    if (changeData.uris != undefined) {
      for(let i=0;i<changeData.uris.length;i++) {
        realPath.push(FileUtils.getPathFromUri(getContext(), changeData.uris[i])!);
      }
    }

    let extraRealPath:Array<string> = [];
    if (changeData.extraUris != undefined) {
      for(let i=0;i<changeData.extraUris.length;i++) {
        extraRealPath.push(FileUtils.getPathFromUri(getContext(), changeData.extraUris[i])!);
      }
    }

    if (changeData.uris != undefined) {
      map.set('uris', realPath);
    }

    if (changeData.extraUris != undefined) {
      map.set('extraUris', extraRealPath);
    }
    PhotoManagerNotifyPlugin.channel?.invokeMethod('change', map);
  }

}

const TAG = "FileUtils";

class FileUtils {
  static getPathFromUri(context: common.Context | null, uri: string, defExtension?: string) {
    Log.i(TAG, "getPathFromUri : " + uri);
    let inputFile: fs.File;
    try {
      inputFile = fs.openSync(uri);
    } catch (err) {
      Log.e(TAG, "open uri file failed err:" + err)
      return null;
    }
    if (inputFile == null) {
      return null;
    }
    const uuid = util.generateRandomUUID();
    if (!context) {
      return
    }
    {
      const targetDirectoryPath = context.cacheDir + "/" + uuid;
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
      const outputFile = fs.openSync(outputFilePath, fs.OpenMode.CREATE);
      try {
        Log.i(TAG, "copyFileSync inputFile fd:" + inputFile.fd + " outputFile fd:" + outputFile.fd);
        fs.copyFileSync(inputFile.fd, outputFilePath);
      } catch (err) {
        Log.e(TAG, "copyFileSync failed err:" + err);
        return null;
      } finally {
        fs.closeSync(inputFile);
        fs.closeSync(outputFile);
      }
      return outputFilePath;
    }
  }
}
