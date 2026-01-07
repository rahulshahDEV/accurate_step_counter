// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'step_log_source.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StepLogSourceAdapter extends TypeAdapter<StepLogSource> {
  @override
  final int typeId = 1;

  @override
  StepLogSource read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return StepLogSource.foreground;
      case 1:
        return StepLogSource.background;
      case 2:
        return StepLogSource.terminated;
      default:
        return StepLogSource.foreground;
    }
  }

  @override
  void write(BinaryWriter writer, StepLogSource obj) {
    switch (obj) {
      case StepLogSource.foreground:
        writer.writeByte(0);
        break;
      case StepLogSource.background:
        writer.writeByte(1);
        break;
      case StepLogSource.terminated:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepLogSourceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
