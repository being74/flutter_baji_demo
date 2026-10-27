/// Device -> APP 方向的 JSON 数据域。
sealed class DeviceMessage {
  const DeviceMessage();
}

class ActivationMessage extends DeviceMessage {
  const ActivationMessage(this.activated);

  final bool activated;
}

class VersionMessage extends DeviceMessage {
  const VersionMessage(this.version);

  final String version;
}

class DeviceInfoMessage extends DeviceMessage {
  const DeviceInfoMessage({
    this.totalSpace,
    this.freeSpace,
    this.devName,
    this.width,
    this.height,
    this.roundScreen,
    this.brand,
  });

  final int? totalSpace;
  final int? freeSpace;
  final String? devName;
  final int? width;
  final int? height;
  final bool? roundScreen;
  final int? brand;
}

/// 设备下发的 12 位身份码，APP 需回 0x0e/Ret 确认。
class IdentityCheckMessage extends DeviceMessage {
  const IdentityCheckMessage(this.code);

  final String code;
}

class IdentityResultMessage extends DeviceMessage {
  const IdentityResultMessage(this.valid);

  final bool valid;
}

class UnknownMessage extends DeviceMessage {
  const UnknownMessage(this.type, this.raw);

  final int type;
  final String raw;
}
