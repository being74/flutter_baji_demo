
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { BajiVideoChannel } from '../plugins/BajiVideoPlugin';

export default class EntryAbility extends FlutterAbility {
  private bajiVideoChannel: BajiVideoChannel | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    this.bajiVideoChannel = new BajiVideoChannel();
    this.bajiVideoChannel.attach(flutterEngine.dartExecutor.getBinaryMessenger());
  }

  onDestroy() {
    this.bajiVideoChannel?.detach();
    this.bajiVideoChannel = null;
    super.onDestroy();
  }
}
