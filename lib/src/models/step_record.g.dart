// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'step_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StepRecordAdapter extends TypeAdapter<StepRecord> {
  @override
  final int typeId = 1;

  @override
  StepRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StepRecord(
      stepCount: fields[0] as int,
      fromTime: fields[1] as DateTime,
      toTime: fields[2] as DateTime,
      source: fields[3] as StepRecordSource,
      confidence: fields[4] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, StepRecord obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.stepCount)
      ..writeByte(1)
      ..write(obj.fromTime)
      ..writeByte(2)
      ..write(obj.toTime)
      ..writeByte(3)
      ..write(obj.source)
      ..writeByte(4)
      ..write(obj.confidence);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
