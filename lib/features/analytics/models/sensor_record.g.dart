// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sensor_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SensorRecordAdapter extends TypeAdapter<SensorRecord> {
  @override
  final typeId = 1;

  @override
  SensorRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SensorRecord(
      timestamp: fields[0] as DateTime,
      fan1Rpm: (fields[1] as num?)?.toInt(),
      fan2Rpm: (fields[2] as num?)?.toInt(),
      cpuTempC: (fields[3] as num?)?.toDouble(),
      gpuTempC: (fields[4] as num?)?.toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, SensorRecord obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.fan1Rpm)
      ..writeByte(2)
      ..write(obj.fan2Rpm)
      ..writeByte(3)
      ..write(obj.cpuTempC)
      ..writeByte(4)
      ..write(obj.gpuTempC);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
