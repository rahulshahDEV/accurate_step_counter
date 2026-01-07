// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'step_log_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StepLogEntryAdapter extends TypeAdapter<StepLogEntry> {
  @override
  final int typeId = 0;

  @override
  StepLogEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StepLogEntry(
      stepCount: fields[0] as int,
      fromTime: fields[1] as DateTime,
      toTime: fields[2] as DateTime,
      source: fields[3] as StepLogSource,
      sourceName: fields[4] as String,
      confidence: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, StepLogEntry obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.stepCount)
      ..writeByte(1)
      ..write(obj.fromTime)
      ..writeByte(2)
      ..write(obj.toTime)
      ..writeByte(3)
      ..write(obj.source)
      ..writeByte(4)
      ..write(obj.sourceName)
      ..writeByte(5)
      ..write(obj.confidence);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepLogEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
