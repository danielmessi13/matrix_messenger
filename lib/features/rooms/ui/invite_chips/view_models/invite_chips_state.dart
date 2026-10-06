import 'package:equatable/equatable.dart';

enum InviteChipStatus { checking, found, unknown, invalidFormat, notFound }

final class InviteChip extends Equatable {
  const InviteChip(this.id, this.status, [this.displayName]);

  final String id;

  final InviteChipStatus status;

  final String? displayName;

  bool get isError =>
      status == InviteChipStatus.invalidFormat ||
      status == InviteChipStatus.notFound;

  bool get blocksSubmit => isError || status == InviteChipStatus.checking;

  @override
  List<Object?> get props => [id, status, displayName];
}

final class InviteChipsState extends Equatable {
  const InviteChipsState({this.chips = const [], this.query = ''});

  final List<InviteChip> chips;

  final String query;

  bool get hasPendingQuery => query.trim().isNotEmpty;

  bool get hasError => chips.any((chip) => chip.isError);

  bool get hasUnknown =>
      chips.any((chip) => chip.status == InviteChipStatus.unknown);

  bool get blocksSubmit => chips.any((chip) => chip.blocksSubmit);

  List<String> get ids => [for (final chip in chips) chip.id];

  List<String> get invalidFormatIds => _idsWith(InviteChipStatus.invalidFormat);

  List<String> get notFoundIds => _idsWith(InviteChipStatus.notFound);

  List<String> get unknownIds => _idsWith(InviteChipStatus.unknown);

  List<String> _idsWith(InviteChipStatus status) => [
    for (final chip in chips)
      if (chip.status == status) chip.id,
  ];

  InviteChipsState copyWith({List<InviteChip>? chips, String? query}) =>
      InviteChipsState(chips: chips ?? this.chips, query: query ?? this.query);

  @override
  List<Object?> get props => [chips, query];
}
