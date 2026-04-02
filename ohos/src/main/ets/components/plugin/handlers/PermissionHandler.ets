import { MethodCall } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import PhotoManagerPlugin from '../PhotoManagerPlugin';
import { HandlerBase, MethodCallHandlerBase } from './HandlerBase';
import { Permissions, abilityAccessCtrl, Want, PermissionRequestResult } from '@kit.AbilityKit';

export class PermissionHandler extends HandlerBase implements MethodCallHandlerBase {
  private static ignoreCheck: boolean = false;
  private static readonly deniedPermissionState = 2;
  private static readonly grantedPermissionState = 3;
  private static readonly permissionGranted = 0;

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<boolean> {
    switch (call.method) {
      case 'openSetting': {
        if (this.uiContext == null) {
          console.warn('openSetting skip: uiContext is null');
          result.success(false);
          break;
        }

        let applicationInfo = this.uiContext.applicationInfo;
        let wantInfo: Want = {
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: 'application_info_entry',
          parameters: {
            pushParams: applicationInfo.name
          }
        }
        try {
          await this.uiContext.startAbility(wantInfo);
          result.success(true);
        } catch (err) {
          console.error(`openSetting failed: ${err}`);
          result.success(false);
        }
      }
        break;
      case 'requestPermissionExtend': {
        let args: Map<string, ESObject> = call.args;
        let ohosPermissions: Array<Permissions> = args.get('ohosPermissions');

        if (Array.isArray(ohosPermissions)) {
          if (PermissionHandler.hasGrantedPermissions(ohosPermissions)) {
            result.success(PermissionHandler.grantedPermissionState);
            break;
          }

          if (!PhotoManagerPlugin.uiContext) {
            console.warn('requestPermissionExtend skip: uiContext is null (no UI context available)');
            result.success(PermissionHandler.deniedPermissionState);
            break;
          }

          let granted = await PermissionHandler.permissionCheck(ohosPermissions);
          if (granted) {
            result.success(PermissionHandler.grantedPermissionState);
          }
          else {
            result.success(PermissionHandler.deniedPermissionState);
          }
        } else {
          result.error('102', 'permissions is not List<String>', 'make sure you pass the right permissions');
        }
      }
        break;
      case 'ignorePermissionCheck': {
        let args: Map<string, ESObject> = call.args;
        PermissionHandler.ignoreCheck = args.get('ignore');
        result.success(null);
      }
        break;
      default:
        return false;
    }

    return true;
  }

  static async permissionReadCheck(): Promise<boolean> {
    return PermissionHandler.permissionCheck(['ohos.permission.READ_IMAGEVIDEO',"ohos.permission.MEDIA_LOCATION"]);
  }

  static async permissionWriteCheck(): Promise<boolean> {
    return PermissionHandler.permissionCheck(['ohos.permission.WRITE_IMAGEVIDEO']);
  }

  static async permissionCheck(permissions: Array<Permissions> = ['ohos.permission.READ_IMAGEVIDEO', 'ohos.permission.WRITE_IMAGEVIDEO',"ohos.permission.MEDIA_LOCATION"]): Promise<boolean> {
    if (permissions.length == 0 || PermissionHandler.ignoreCheck) {
      // result.error('101', 'permissions is empty', 'make sure you pass the permissions');
      return true;
    }

    // Query the current grant state first. This does not need a UI context.
    if (PermissionHandler.hasGrantedPermissions(permissions)) {
      return true;
    }

    if (!PhotoManagerPlugin.uiContext) {
      console.warn('permissionCheck skip request: uiContext is null (no UI context available)');
      return false;
    }

    let atManager = abilityAccessCtrl.createAtManager();
    /// dart
    /// The user has not set the app’s authorization status.
    /// notDetermined,

    /// The app isn’t authorized to access the photo library, and the user can’t grant such permission.
    /// restricted,

    /// The user explicitly denied this app access to the photo library.
    /// denied,

    /// The user explicitly granted this app access to the photo library.
    /// authorized,

    /// The user authorized this app for limited photo library access.
    ///
    /// This state only supports iOS 14 and above.
    /// limited,

    /// ohos
    /// The user denied access to the requested feature, permission needs to be
    /// asked first.
    /// denied(-1),

    /// The user granted access to the requested feature.
    /// granted(0),

    /// Invalid request.
    /// invalid(2)
    try {
      let data: PermissionRequestResult = await atManager.requestPermissionsFromUser(PhotoManagerPlugin.uiContext!, permissions,);
      let grantStatus: Array<number> = data.authResults;
      let length: number = grantStatus.length;
      for (let i = 0; i < length; i++) {
        if (grantStatus[i] != PermissionHandler.permissionGranted) {
          return false;
        }
      }
      return true;
    } catch (err) {
      console.error(`requestPermissionsFromUser failed: ${err}`);
      return false;
    }
  }

  private static hasGrantedPermissions(permissions: Array<Permissions>): boolean {
    const context = PhotoManagerPlugin.uiContext ?? PhotoManagerPlugin.context;
    if (!context) {
      return false;
    }

    try {
      const tokenId = context.applicationInfo.accessTokenId;
      if (!tokenId) {
        return false;
      }

      const atManager = abilityAccessCtrl.createAtManager();
      for (let i = 0; i < permissions.length; i++) {
        if (atManager.checkAccessTokenSync(tokenId, permissions[i]) != PermissionHandler.permissionGranted) {
          return false;
        }
      }
      return true;
    } catch (err) {
      console.warn(`checkAccessTokenSync failed: ${err}`);
      return false;
    }
  }
}
