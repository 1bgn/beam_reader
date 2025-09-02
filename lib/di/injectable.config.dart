// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:beam_reader/engine/xml_loader.dart' as _i575;
import 'package:beam_reader/features/reader_screen/appication/reader_screen_controller.dart'
    as _i917;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    gh.lazySingleton<_i575.XmlLoader>(() => _i575.XmlLoader());
    gh.lazySingleton<_i917.ReaderScreenController>(
      () => _i917.ReaderScreenController(gh<_i575.XmlLoader>()),
    );
    return this;
  }
}
