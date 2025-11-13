import { MethodCall, MethodChannel, MethodResult } from "@ohos/flutter_ohos";
import { MethodCallHandlerBase } from "./HandlerBase";
import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { PMProgressHandlerProtocol, PMProgressState } from "./PMProgressHandlerInterface";


export class PMProgressHandler implements PMProgressHandlerProtocol {
  private channel: MethodChannel | null = null;

  constructor(binding:FlutterPluginBinding, index: number) {
    const name = `com.fluttercandies/photo_manager/progress/${index}`;
    this.channel = new MethodChannel(binding.getBinaryMessenger(),name);
  }

  async notify(progress: number, state: PMProgressState) {
    try {
      if(!this.channel) {
        return;
      }
      this.channel?.invokeMethod('notifyProgress', {state:state as number,progress:progress});
    } catch (e) {

    } finally {
      if (state == PMProgressState.Success || state == PMProgressState.Failed) {
        this.channel?.setMethodCallHandler(null);
        this.channel = null;
      }
    }
  }

  dispose() {
    this.channel = null;
  }
}
