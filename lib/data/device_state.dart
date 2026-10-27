/// 设备上报的信息汇总，未知字段保持 null。
class DeviceState {
  const DeviceState({
    this.activated,
    this.version,
    this.totalSpace,
    this.freeSpace,
    this.devName,
    this.width,
    this.height,
    this.roundScreen,
    this.brand,
    this.identityCode,
    this.identityVerified,
  });

  final bool? activated;
  final String? version;
  final int? totalSpace;
  final int? freeSpace;
  final String? devName;
  final int? width;
  final int? height;
  final bool? roundScreen;
  final int? brand;
  final String? identityCode;
  final bool? identityVerified;

  DeviceState copyWith({
    bool? activated,
    String? version,
    int? totalSpace,
    int? freeSpace,
    String? devName,
    int? width,
    int? height,
    bool? roundScreen,
    int? brand,
    String? identityCode,
    bool? identityVerified,
  }) =>
      DeviceState(
        activated: activated ?? this.activated,
        version: version ?? this.version,
        totalSpace: totalSpace ?? this.totalSpace,
        freeSpace: freeSpace ?? this.freeSpace,
        devName: devName ?? this.devName,
        width: width ?? this.width,
        height: height ?? this.height,
        roundScreen: roundScreen ?? this.roundScreen,
        brand: brand ?? this.brand,
        identityCode: identityCode ?? this.identityCode,
        identityVerified: identityVerified ?? this.identityVerified,
      );
}
