import 'dart:io';
import 'dart:math';

import "package:collection/collection.dart";
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import "plant.dart";
import "routes.dart";
import "search.dart";

void main() {
  runApp(Plantz());
}

void createTables(Database db) {
  db.execute(
    "CREATE TABLE IF NOT EXISTS plants(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, frequency INTEGER, snooze INTEGER, region INTEGER, FOREIGN KEY(region) REFERENCES regions(id))",
  );
  db.execute(
    "CREATE TABLE IF NOT EXISTS actions(id INTEGER PRIMARY KEY AUTOINCREMENT, plant_id INTEGER, action TEXT, timestamp INTEGER, FOREIGN KEY(plant_id) REFERENCES plants(id))",
  );
  db.execute(
    "CREATE TABLE IF NOT EXISTS photos(id INTEGER PRIMARY KEY AUTOINCREMENT, plant_id INTEGER, path TEXT, timestamp INTEGER, FOREIGN KEY(plant_id) REFERENCES plants(id))",
  );
  db.execute(
    "CREATE TABLE IF NOT EXISTS regions(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)",
  );
  db.execute("ALTER TABLE plants ADD COLUMN region INTEGER");
}

Future<Database> getDatabase() async {
  return openDatabase(
    join(await getDatabasesPath(), 'plantz.db'),
    onUpgrade: (db, oldversion, newVersion) {
      createTables(db);
    },
    onDowngrade: (db, oldversion, newVersion) {
      createTables(db);
    },
    version: 7,
  );
}

int getCurrentTimestamp() {
  return (DateTime.now().millisecondsSinceEpoch / 1000).round();
}

class Plantz extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plantz',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => MainPage(title: 'Plantz'),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/detail') {
          final PlantDetailPageRouteArguments args = settings.arguments;
          return MaterialPageRoute(
            builder: (context) {
              return PlantDetailPage(
                plant: args.p,
                locations: args.locations,
              );
            },
          );
        }
        return MaterialPageRoute(
          builder: (context) {
            return MainPage();
          },
        );
      },
    );
  }
}

class PlantDetailPage extends StatefulWidget {
  PlantDetailPage({Key key, this.plant, this.locations}) : super(key: key);

  Plant plant;
  Map<String, int> locations;
  @override
  _PlantDetailPageState createState() => _PlantDetailPageState();
}

class _PlantDetailPageState extends State<PlantDetailPage> {
  TextEditingController controller;
  Database db;
  Plant plant;
  Map<String, int> locations;
  List<int> waterings = [];
  TextEditingController frequencyController;
  final picker = ImagePicker();

  Future getImage() async {
    final pickedFile = await picker.getImage(
        source: ImageSource.camera, preferredCameraDevice: CameraDevice.rear);
    int ts = getCurrentTimestamp();
    await db.insert(
      'photos',
      {'plant_id': plant.id, 'path': pickedFile.path, 'timestamp': ts},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    setState(() {
      plant.imagePaths.insert(0, pickedFile.path);
    });
  }

  Future<List<int>> loadPlant() async {
    db = await getDatabase();
    var results = await db.query('actions',
        where: "plant_id = ? and action = 'water'", whereArgs: [plant.id]);
    var ret =
        List.generate(results.length, (i) => results[i]['timestamp'] as int);
    ret.sort((t1, t2) => t2 - t1);
    return ret;
  }

  @override
  void initState() {
    super.initState();
    plant = widget.plant;
    locations = Map.from(widget.locations);
    locations["None"] = -1;
    controller = TextEditingController(text: plant.name);
    frequencyController =
        TextEditingController(text: plant.frequency.toString());

    loadPlant().then((result) {
      setState(() {
        waterings = result;
      });
    });
  }

  Future<void> water() async {
    int ts = getCurrentTimestamp();
    await db.insert(
      'actions',
      {'plant_id': plant.id, 'action': 'water', 'timestamp': ts},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.update('plants', {'snooze': 0},
        where: "id = ?", whereArgs: [plant.id]);
    setState(() {
      waterings.insert(0, ts);
      plant.snooze = 0;
    });
  }

  Future<void> updateFrequency(int days) async {
    days = days < 0 ? 0 : days;
    await db.update('plants', {'frequency': days},
        where: "id = ?", whereArgs: [plant.id]);
    plant.frequency = days;
  }

  Future<void> updateName(String name) async {
    await db.update('plants', {'name': name},
        where: "id = ?", whereArgs: [plant.id]);
    plant.name = name;
  }

  Future<void> updateLocation(int id) async {
    await db.update('plants', {'region': id},
        where: "id = ?", whereArgs: [plant.id]);
    setState(() {
      plant.location = id;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> widgets = [
      TextField(
        decoration: new InputDecoration(labelText: "Name"),
        controller: controller,
        keyboardType: TextInputType.text,
        onChanged: (s) {
          updateName(controller.text);
        },
      ),
      TextField(
        decoration: new InputDecoration(labelText: "Frequency"),
        controller: frequencyController,
        keyboardType: TextInputType.number,
        onChanged: (s) {
          updateFrequency(int.tryParse(frequencyController.text) ?? 0);
        },
      ),
      new DropdownButton<int>(
        items: locations
            .map((String value, int idx) {
              if (idx < -1) {
                return MapEntry(idx, null);
              }
              return MapEntry(
                  idx,
                  DropdownMenuItem<int>(
                    value: idx,
                    child: new Text(value),
                  ));
            })
            .values
            .where((t) => t != null)
            .toList(),
        value: plant.location,
        onChanged: (l) {
          updateLocation(l);
        },
      ),
      FlatButton(
        child: Text('Add Image'),
        onPressed: () {
          getImage();
        },
      )
    ];
    widgets.addAll(plant.imagePaths.map((p) => Image.file(File(p))));
    widgets.addAll(waterings
        .map((timestamp) => Card(
              child: ListTile(
                title: Text(DateFormat('d MMM y – kk:mm:ss').format(
                    new DateTime.fromMillisecondsSinceEpoch(timestamp * 1000))),
              ),
            ))
        .toList());
    return Scaffold(
      appBar: AppBar(
        title: Text(plant.name),
      ),
      body: Center(child: ListView(children: widgets)),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          water();
        },
        tooltip: 'Water',
        child: Icon(Icons.bubble_chart),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  MainPage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  TextEditingController frequencyController;
  TextEditingController addController;
  TextEditingController regionController;
  List<Plant> plants = [];
  Database db;
  int selectedLocation = -1;
  Map<String, int> locations = {};

  Future<void> addPlant(String plant, int frequency, int region) async {
    if (plant.isEmpty) {
      return;
    }
    var id = await db.insert(
      'plants',
      {
        'name': plant,
        'frequency': frequency,
        'region': locations.length > 2 ? region : -1
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    setState(() {
      plants.add(Plant(plant, id, frequency, 0, [], 0, region));
      sortPlantList(plants);
    });
  }

  Future<void> addRegion(String name) async {
    if (name.isEmpty) {
      return;
    }
    var id = await db.insert(
      'regions',
      {'name': name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    setState(() {
      locations[name] = id;
      locations.remove('Add new region');
      locations['Add new region'] = -2;
    });
  }

  int plantSort(Plant p1, Plant p2, int now) {
    var p1time = p1.ts + p1.frequency * 86400;
    var p2time = p2.ts + p2.frequency * 86400;
    if (p1.frequency == 0) {
      p1time = now + 1;
    }
    if (p2.frequency == 0) {
      p2time = now + 1;
    }
    p1time = max(p1time, p1.snooze);
    p2time = max(p2time, p2.snooze);
    if ((p1time <= now && p2time <= now) || (p1time > now && p2time > now)) {
      return p1.name.toLowerCase().compareTo(p2.name.toLowerCase());
    }
    if (p1time <= now) {
      return -1;
    }
    return 1;
  }

  void sortPlantList(List<Plant> list) {
    var now = getCurrentTimestamp();
    list.sort((Plant a, Plant b) => plantSort(a, b, now));
  }

  Future<List<Plant>> loadPlants() async {
    db = await getDatabase();
    final List<Map<String, dynamic>> maps = await db.rawQuery(
        "SELECT plants.id as id, name, frequency, action, max(timestamp) as ts, snooze, region from plants left outer join actions on plants.id = plant_id group by plants.id, name, frequency, action");
    final List<Map<String, dynamic>> photos =
        await db.rawQuery("SELECT * from photos");
    var groupedPhotos = groupBy(photos, (photo) => photo['plant_id']);
    final List<Map<String, dynamic>> regions =
        await db.rawQuery("SELECT * from regions");
    locations = {'All': -1};
    for (var i = 0; i < regions.length; ++i) {
      locations[regions[i]['name']] = regions[i]['id'];
    }
    locations['Add new region'] = -2;
    var ret = List.generate(
      maps.length,
      (i) => Plant(
        maps[i]['name'],
        maps[i]['id'],
        maps[i]['frequency'] ?? 0,
        maps[i]['ts'] ?? 0,
        groupedPhotos.containsKey(maps[i]['id'])
            ? () {
                var photo = groupedPhotos[maps[i]['id']];
                photo.sort((v1, v2) => v2['timestamp'] - v1['timestamp']);
                return photo.map((v) => v['path'].toString()).toList();
              }()
            : [],
        maps[i]['snooze'] ?? 0,
        maps[i]['region'] ?? -1,
      ),
    );
    sortPlantList(ret);
    return ret;
  }

  @override
  void initState() {
    super.initState();

    frequencyController = TextEditingController(text: "7");
    addController = TextEditingController();
    regionController = TextEditingController();
    loadPlants().then((result) {
      setState(() {
        plants = result;
      });
    });
  }

  bool needsWatering(Plant p) {
    if (p.frequency == 0) {
      return false;
    }
    var now = getCurrentTimestamp();
    var waterTime = now - p.ts - p.frequency * 86400;
    if (p.snooze > 0 && p.snooze > now && waterTime > 0) {
      return false;
    }
    return waterTime > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          new DropdownButton<int>(
            items: locations
                .map((String value, int idx) {
                  return MapEntry(
                      idx,
                      DropdownMenuItem<int>(
                        value: idx,
                        child: new Text(value),
                      ));
                })
                .values
                .toList(),
            value: selectedLocation,
            onChanged: (l) {
              if (l == -2) {
                showDialog(
                    child: new Dialog(
                      child: new Column(
                        children: <Widget>[
                          new TextField(
                            decoration: new InputDecoration(labelText: "Name"),
                            controller: regionController,
                          ),
                          new FlatButton(
                            child: new Text("Add"),
                            onPressed: () {
                              addRegion(regionController.text);
                              Navigator.pop(context);
                            },
                          ),
                          new FlatButton(
                            child: new Text("Cancel"),
                            onPressed: () {
                              Navigator.pop(context);
                            },
                          )
                        ],
                      ),
                    ),
                    context: context);
                return;
              }
              setState(() {
                selectedLocation = l;
              });
            },
          ),
          IconButton(
            onPressed: () {
              showSearch(
                      context: context,
                      delegate: PlantSearch(plants, locations))
                  .then((e) {
                loadPlants().then((result) {
                  setState(() {
                    plants = result;
                  });
                });
              });
            },
            icon: Icon(Icons.search),
          )
        ],
        title: Text("${widget.title} (${plants.length})"),
      ),
      body: Center(
        child: RefreshIndicator(
          child: ListView(
              children: plants
                  .where((p) {
                    if (selectedLocation == -1) {
                      return true;
                    }
                    return p.location == selectedLocation;
                  })
                  .map((p) => Card(
                        child: Material(
                            color: needsWatering(p) ? Colors.red : null,
                            child: ListTile(
                                contentPadding: p.imagePaths.isNotEmpty
                                    ? EdgeInsets.only(left: 0.0, right: 16.0)
                                    : null,
                                leading: p.imagePaths.isNotEmpty
                                    ? Image.file(File(p.imagePaths.first),
                                        fit: BoxFit.fitHeight)
                                    : FlutterLogo(),
                                title: Text(p.name),
                                trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                          //overlayColor:Colors.green,
                                          child: Padding(
                                              padding: EdgeInsets.only(
                                                  right: 12.0,
                                                  top: 12.0,
                                                  bottom: 12.0),
                                              child: Icon(Icons.bubble_chart)),
                                          onTap: () {
                                            var ts = getCurrentTimestamp();
                                            db
                                                .insert(
                                              'actions',
                                              {
                                                'plant_id': p.id,
                                                'action': 'water',
                                                'timestamp': ts
                                              },
                                              conflictAlgorithm:
                                                  ConflictAlgorithm.replace,
                                            )
                                                .then((e) {
                                              setState(() {
                                                p.ts = ts;
                                                sortPlantList(plants);
                                              });
                                            });
                                          }),
                                      InkWell(
                                          child: Padding(
                                              padding: EdgeInsets.only(
                                                  top: 12.0, bottom: 12.0),
                                              child: Icon(Icons.snooze)),
                                          onTap: () {
                                            if (p.frequency == 0) {
                                              return;
                                            }
                                            var ts =
                                                getCurrentTimestamp() + 86400;
                                            db
                                                .update(
                                                    'plants', {'snooze': ts},
                                                    where: "id = ?",
                                                    whereArgs: [p.id])
                                                .then((e) {
                                              setState(() {
                                                p.snooze = ts;
                                                sortPlantList(plants);
                                              });
                                            });
                                          }),
                                    ]),
                                onTap: () {
                                  Navigator.pushNamed(context, '/detail',
                                          arguments:
                                              PlantDetailPageRouteArguments(
                                                  p, locations))
                                      .then((e) {
                                    loadPlants().then((result) {
                                      setState(() {
                                        plants = result;
                                      });
                                    });
                                  });
                                })),
                      ))
                  .toList()),
          onRefresh: () {
            return loadPlants().then((result) {
              setState(() {
                plants = result;
              });
            });
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
              builder: (context) {
                var editLocation = selectedLocation > 0
                    ? selectedLocation
                    : locations.values.reduce((v, e) => max(v, e));
                return StatefulBuilder(builder: (context, setState) {
                  return new Dialog(
                    child: new Column(
                      children: <Widget>[
                        new TextField(
                          decoration: new InputDecoration(labelText: "Name"),
                          controller: addController,
                        ),
                        new TextField(
                          decoration:
                              new InputDecoration(labelText: "Frequency"),
                          keyboardType: TextInputType.number,
                          controller: frequencyController,
                        ),
                        locations.length > 2
                            ? new DropdownButton<int>(
                                items: locations
                                    .map((String value, int idx) {
                                      if (idx < 0) {
                                        return MapEntry(idx, null);
                                      }
                                      return MapEntry(
                                          idx,
                                          DropdownMenuItem<int>(
                                            value: idx,
                                            child: new Text(value),
                                          ));
                                    })
                                    .values
                                    .where((t) => t != null)
                                    .toList(),
                                value: editLocation,
                                onChanged: (l) {
                                  setState(() {
                                    editLocation = l;
                                  });
                                  print(l);
                                  print(editLocation);
                                },
                              )
                            : null,
                        new FlatButton(
                          child: new Text("Add"),
                          onPressed: () {
                            addPlant(
                                addController.text,
                                int.tryParse(frequencyController.text) ?? 7,
                                editLocation);
                            addController.text = '';
                            frequencyController.text = '7';
                            Navigator.pop(context);
                          },
                        ),
                        new FlatButton(
                          child: new Text("Cancel"),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                        )
                      ],
                    ),
                  );
                });
              },
              context: context);
        },
        tooltip: 'Add plant',
        child: Icon(Icons.add),
      ),
    );
  }
}
