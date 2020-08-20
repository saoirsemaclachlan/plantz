import 'dart:math';

import 'package:flutter/material.dart';
import "plant.dart";

class PlantSearch extends SearchDelegate {
  final List<Plant> plants;

  PlantSearch(this.plants);

  @override
  List<Widget> buildActions(BuildContext context) {
    return <Widget>[
      IconButton(
        icon: Icon(Icons.close),
        onPressed: () {
          query = "";
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () {
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return Container(
      child: doSearch(),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return doSearch();
  }

  double countMatches(List<String> terms, String name) {
    return terms.map((term) {
      var plantTerms = name.split(RegExp(r"\s+"));
      return plantTerms
          .map((p) =>
              p.toLowerCase().contains(term) ? term.length / p.length : 0.0)
          .reduce(max);
    }).reduce((a, b) => a + b);
  }

  ListView doSearch() {
    List<Plant> results = [];
    if (query.isNotEmpty) {
      var terms = query
          .split(RegExp(r"\s+"))
          .where((t) => t.isNotEmpty)
          .map((t) => t.toLowerCase())
          .toList();
      results.addAll(plants.where(
        (plant) => terms.any((term) => plant.name.toLowerCase().contains(term)),
      ));
      results.sort((p1, p2) {
        var p1count = countMatches(terms, p1.name);
        var p2count = countMatches(terms, p2.name);
        if (p1count != p2count) {
          return p2count > p1count ? 1 : -1;
        }
        return p1.name.toLowerCase().compareTo(p2.name.toLowerCase());
      });
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text(
            results[index].name,
          ),
          onTap: () {
            Navigator.pushNamed(context, '/detail', arguments: results[index]);
          },
        );
      },
    );
  }
}
