import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'package:args/args.dart';

final String baseURL = "http://api.highcharts.com/option/highcharts/child/";
final String baseMethodsURL = "http://api.highcharts.com/object/highcharts-obj/child/";

final Map<String, String> propertyTypesDirtyFixes = {
  "PlotOptionsSeries.pointStart": "dynamic"
};

main(List<String> args) async {

  var parser = new ArgParser ();
  parser.addOption('output', abbr: 'o', help:'Output directory to store generated files');
  parser.addFlag('help', abbr:'h', help:'Show this help');

  var parsedArguments = parser.parse(args);

  if (parsedArguments['help']) {
    print(parser.usage);
    return;
  }
  if (parsedArguments['output'] == null) {
    print ("Output folder must be specified");
    print(parser.usage);
    return;
  }

  var outputDirectory = parsedArguments['output'];

  List<String> topLevelClasses = ["chart", "credits", "data", "drilldown", "exporting", "labels", "legend",
                                  "loading", "navigation", "noData", "pane", "plotOptions", "series",
                                  "series<area>", "series<arearange>", "series<areaspline>",
                                  "series<areasplinerange>", "series<bar>", "series<boxplot>",
                                  "series<bubble>", "series<column>", "series<columnrange>",
                                  "series<errorbar>", "series<funnel>", "series<gauge>", "series<heatmap>",
                                  "series<line>", "series<pie>", "series<polygon>", "series<pyramid>",
                                  "series<scatter>", "series<solidgauge>", "series<spline>",
                                  "series<treemap>", "series<waterfall>",
                                  "subtitle",
                                  "title", "tooltip", "xAxis", "yAxis"];

  StringBuffer api = new StringBuffer();

  File libraryAndImportsTemplate = new File("bin/templates/library_and_imports.txt");
  api.write(libraryAndImportsTemplate.readAsStringSync());
  api.writeln("");

  // Creation of the "src" directory where all the dart files will be stored
  new Directory("$outputDirectory/src/").createSync();

  await Future.forEach(topLevelClasses, (String topLevelClass) async {
    var sb = new StringBuffer();
    sb.writeln("part of highcharts;");
    sb.writeln("");
    sb.write(await generateApi(topLevelClass));
    var fileName = camelCaseToLowerCaseUnderscore(dashesToCamelCase(topLevelClass));
    api.writeln ("part 'src/${fileName}.dart';");
    File file = new File ('$outputDirectory/src/$fileName.dart');
    file.writeAsStringSync(sb.toString());
  });

  api.write(await generateHighchartsChartApi());
  api.writeln("");
  File hardcodedClassesTemplate = new File("bin/templates/hardcoded_classes.txt");
  api.write(hardcodedClassesTemplate.readAsStringSync());

  File file = new File('$outputDirectory/highcharts.dart');
  file.writeAsStringSync(api.toString());

}

String getMethodReturnType (String jsReturnType, String propertyName, bool isParent) {
  String type = getType(jsReturnType, propertyName, isParent);
  if (type == "JsObject") {
    type = "dynamic";
  }
  return type;
}

String getType (String jsReturnType, String propertyName, bool isParent) {
  String out = "dynamic";
  if (jsReturnType == null && isParent) {
    out = startUpperCase(dashesToCamelCase(propertyName));
  }
  else {
    switch (jsReturnType) {
      case "Boolean":
        out = "bool";
        break;
      case "String":
        out = "String";
        break;
      case "Number":
        out = "num";
        break;
      case "Color":
        out = "dynamic";  // A color can be a String or an object (see: http://www.highcharts.com/docs/chart-design-and-style/colors)
        break;
      case "Function":
        out = "Function";
        break;
      case "Array<Boolean>":
        out = "List<bool>";
        break;
      case "Array<String>":
        out = "List<String>";
        break;
      case "Array<Number>":
        out = "List<num>";
        break;
      case "Array<Object>":
        out = "List<dynamic>";
        break;
      case "Array<Color>":
        out = "List<String>";
        break;
      case "Array":
        out = "List";
        break;
      case "Object":
        out = "dynamic";
        break;
    }
  }
  return out;
}

String startUpperCase (String text) {
  return text[0].toUpperCase() + text.substring(1);
}

String processSeriesClass (String clazz) {
  RegExp seriesClassRegex = new RegExp (r"series<(.*)>");
  Iterable<Match> matches = seriesClassRegex.allMatches(clazz);
  var formattedClass = clazz;
  if (matches.length > 0) {
    formattedClass = startUpperCase(matches.elementAt(0).group(1)) + "Series";
  }
  return formattedClass;
}

String dashesToCamelCase (String dashes) {
  var splitted = dashes.split("-");
  var out = "";
  splitted.forEach((String dash) {
    var formattedDash = processSeriesClass(dash);
    out = out + startUpperCase(formattedDash);
  });
  return out;
}

String camelCaseToLowerCaseUnderscore (String camel) {
  var regex = new RegExp("([a-z])([A-Z]+)");
  String out = camel.replaceAllMapped(regex, (Match match) {
    return "${match.group(1)}_${match.group(2)}";
  });
  return out.toLowerCase();
}

bool isSeriesClass (String className) {
  RegExp regex = new RegExp(r".+Series$");
  return regex.allMatches(className).length > 0;
}

bool isAxisClass (String className) {
  return className.toLowerCase == "xaxis" || className.toLowerCase() == "yaxis";
}

List<String> generatePropertiesAndReturnPropNames (StringBuffer sb, List apiJson,
                                              String className, List<String> parents) {
  List<String> propNames = [];

  apiJson.forEach((Map propertyApi) {
    String propName = propertyApi['fullname'].split(
        "\.")[propertyApi['fullname']
        .split("\.")
        .length - 1];
    String type = getType(propertyApi['returnType'], propertyApi['name'], propertyApi['isParent']);

    // Wait, let's check out dirty type fixes for this property:
    if (propertyTypesDirtyFixes["$className.$propName"]!=null) {
      type = propertyTypesDirtyFixes["$className.$propName"];
    }

    if (propName != "") {
      sb.writeln("  /** \n   * ${propertyApi['description']} \n   */");
      if (propertyApi['deprecated'] != null && propertyApi['deprecated'])
        sb.writeln("  @deprecated");
      sb.writeln("  external $type get $propName;");
      if (propertyApi['deprecated'] != null && propertyApi['deprecated'])
        sb.writeln("  @deprecated");
      sb.writeln("  external void set $propName ($type a_$propName);");
      if (propertyApi['isParent']) {
        parents.add(propertyApi['name']);
      }
      propNames.add(propName);
    }
  });
  return propNames;
}

void generateMethods (StringBuffer sb, List apiMethodsJson, String className, List<String> propNames, List<String> parents) {
  apiMethodsJson.forEach((Map methodApi) {
    if (methodApi['type']=="method") {
      List<String> methodNameSplitted = methodApi['fullname'].split(r".");
      String methodName = methodNameSplitted[methodNameSplitted.length - 1];
      var alreadyInProperties = propNames.contains(methodName);
      if (!alreadyInProperties) {
        List<String> paramsSplitted = [];
        if (methodApi['params'] != null) {
          paramsSplitted = (methodApi['params'] as String)
              .replaceAll(r"(", "")
              .replaceAll(r")", "")
              .replaceAll(r"[", "")
              .replaceAll(r"]", "")
              .split(",");
        }
        String convertedParams = "";
        bool first = true;
        paramsSplitted.forEach((String param) {
          List<String> splitted = param.trim().split(" ");
          if (splitted != null && splitted.length == 2) {
            String type = splitted[0];
            String name = splitted[1].replaceAll(r"|", "_or_");
            String convertedType = getMethodReturnType(type, "", false);
            convertedParams = convertedParams +
                "${first ? '' : ','} ${convertedType} ${name}";
            first = false;
          }
          else {
            /* REMOVED THIS WARNING. NOT NEEDED ANYMORE: print(
                "Warning: param \"$param\" has not been processed when parsing methods for $child"); */
          }
        });
        String convertedReturnType = methodApi['returnType'] == null ||
            methodApi['returnType'] == '' ? "void" : getMethodReturnType(
            methodApi['returnType'], "", false);
        sb.writeln("  /** ");
        sb.writeln("  * ${methodApi['paramsDescription']}");
        sb.writeln("  */");
        sb.writeln(

            "  external $convertedReturnType $methodName ($convertedParams);");
      }
    }
  });
}

Future<String> generateHighchartsChartApi () async {
  String child = "chart";
  List apiJson = await getApiJson(child);
  List apiMethodsJson = await getApiMethodsJson (child);
  List<String> parents = [];
  StringBuffer sb = new StringBuffer();

  if (apiJson != null) {
    sb.writeln("@JS('Highcharts.Chart')");
    sb.writeln("class HighchartsChart {");
    String className = "HighchartsChart";

    sb.writeln("  external HighchartsChart (ChartOptions options);");

    sb.writeln("  external List<Series> get series;");
    sb.writeln("  external List<Axis> get axes;");

    List<String> propNames = generatePropertiesAndReturnPropNames(sb, apiJson, className, parents);
    generateMethods(sb, apiMethodsJson, className, propNames, parents);

    sb.writeln("}");

    /* NO ES NECESARIO GENERAR TODAS LAS CLASES HIJAS PORQUE YA LO VA A HACER LA CLASE chart QUE ESTÁ COMO TOP LEVEL CLASS
    await Future.forEach(parents, (String property) async {
      sb.write(await generateApi(property));
    });
    */
  }

  return sb.toString();
}

Future<String> generateApi (String child) async {
  List apiJson = await getApiJson(child);
  List apiMethodsJson = await getApiMethodsJson (child);
  List<String> parents = [];
  StringBuffer sb = new StringBuffer();

  if (apiJson != null) {
    sb.writeln("@JS()");
    sb.writeln("@anonymous");

    String className = dashesToCamelCase(child);

    if (isAxisClass(className)) {
      sb.writeln("class $className extends Axis {");
    }
    else if (isSeriesClass(className)) {
      sb.writeln("class $className extends Series {");
    }
    else if (className == "Series") {
      sb.writeln("class $className extends PlotOptions {");
    }
    else {
      sb.writeln("class $className {");
    }
    sb.writeln("  external factory $className ();");

    List<String> propNames = generatePropertiesAndReturnPropNames(sb, apiJson, className, parents);
    generateMethods(sb, apiMethodsJson, className, propNames, parents);

    sb.writeln("}");

    await Future.forEach(parents, (String property) async {
      sb.write(await generateApi(property));
    });
  }

  return sb.toString();
}

Future<List> getApiJson (String child) async {
  var url = "$baseURL$child";
  var response = await http.get(url);
  List out = null;
  try {
    out = JSON.decode(response.body);
  }
  catch (e) {
    print ("Error processing $child");
  }
  return out;
}

Future<List> getApiMethodsJson (String child) async {
  var url = "$baseMethodsURL${startUpperCase(child)}";
  var response = await http.get(url);
  List out = null;
  try {
    out = JSON.decode(response.body);
  }
  catch (e) {
    print ("Error processing methods for $child");
  }
  return out;
}