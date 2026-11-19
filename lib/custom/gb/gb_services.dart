// GameBanana tab — the few things the tab and its dialogs share.

import 'package:http/http.dart' as http;
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:no_reload_mod_manager/utils/archive_manager.dart';
import 'package:no_reload_mod_manager/utils/constant_var.dart';
import 'package:no_reload_mod_manager/utils/get_cloud_data.dart';
import 'package:path/path.dart' as p;

/// Index of this tab in the tab bar: Keybinds 0, Mods 1, GameBanana 2, Settings 3.
const int gbTabIndex = 2;

/// GameBanana's id for each game NRMM supports (checked against their API).
const Map<TargetGame, int> gbGameIds = {
  TargetGame.Genshin_Impact: 8552,
  TargetGame.Honkai_Star_Rail: 18366,
  TargetGame.Zenless_Zone_Zero: 19567,
  TargetGame.Wuthering_Waves: 20357,
  TargetGame.Arknights_Endfield: 21842,
};

/// The app's one shared HTTP client.
http.Client get gbHttpClient => httpClient.client;

/// Not final so tests can swap in a fake.
GbApi gbApi = GbApi(httpClient.client);

Future<bool> gbSevenZipExtract(String archive, String outDir) async =>
    (await SevenZip.instance.extract(archive, outputDir: outDir)).success;

String gbManagedPath(String modsPath) =>
    p.join(modsPath, ConstantVar.managedFolderName);

/// Files NRMM keeps in a mod folder for the user (custom name, favorite, icon).
/// An update copies these from the old folder to the new one.
final List<String> gbCarryOverFiles = [
  'modname',
  'fav',
  ...ConstantVar.modIconFilenames,
];
