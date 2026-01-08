// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'step_record_source.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StepRecordSourceAdapter extends TypeAdapter<StepRecordSource> {
  @override
  final int typeId = 2;

  @override
  StepRecordSource read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return StepRecordSource.foreground;
      case 1:
        return StepRecordSource.background;
      case 2:
        return StepRecordSource.terminated;
      case 3:
        return StepRecordSource.external;
      default:
        return StepRecordSource.foreground;
    }
  }

  @override
  void write(BinaryWriter writer, StepRecordSource obj) {
    switch (obj) {
      case StepRecordSource.foreground:
        writer.writeByte(0);
        break;
      case StepRecordSource.background:
        writer.writeByte(1);
        break;
      case StepRecordSource.terminated:
        writer.writeByte(2);
        break;
      case StepRecordSource.external:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepRecordSourceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
