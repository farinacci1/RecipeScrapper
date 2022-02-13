import 'dart:convert';

import 'package:mybmr/services/conversion.dart';
import 'package:mybmr/services/toast.dart';
import 'package:web_scraper/web_scraper.dart';

class RecipeScraper {
  /*
  * RecipeScraper should parse web data of approved recipe sits and return
  * title, description, servings, total time, ingredients and instructions
  * */


  static final List<RegExp> _dataSchemes = [
    RegExp(r'(?<=type="application/ld\+json">)(.*?)(?=</script>)',
        multiLine: true, dotAll: true),
  ];



  static Future<Map<String, dynamic>> scrapeUrl(String inputUrl) async {
    Uri urlData = Uri.parse(inputUrl);
    String websiteBaseUrl = urlData.scheme +"://" +  urlData.host;
    String route = urlData.path + urlData.query;

    Map<String, dynamic> jsonData =
        await _processWebpage(websiteBaseUrl, route);

    if (jsonData.isEmpty) {
      return {};
    }
    const List<String> _validKeys = [
      "name",
      "recipeInstructions",
      "recipeIngredient",
      "recipeYield",
      "totalTime",
      "prepTime",
      "cookTime",
      "description"
    ];
    jsonData.removeWhere((key, value) => _validKeys.contains(key) == false);
    jsonData.addAll({"recipeUrl": inputUrl});
    print(jsonData);
    return _prepareData(jsonData);
  }

  static Map<String, dynamic> _prepareData(Map<String, dynamic> jsonData) {
    Map<String, dynamic> processedJson = {};
    int totalTime = 0;
    double servingSize = 0;
    List<String> steps = [];
    if (jsonData.containsKey("totalTime")) {
      totalTime = _processTimeString(jsonData["totalTime"]);
    } else {
      if (jsonData.containsKey("cookTime"))
        totalTime += _processTimeString(jsonData["cookTime"]);
      if (jsonData.containsKey("prepTime"))
        totalTime += _processTimeString(jsonData["prepTime"]);
    }
    if (jsonData.containsKey("recipeYield")) {
      RegExp regex = RegExp(r'([\+\-]*\d*\.*\d+)');
      String numString = regex.stringMatch(jsonData["recipeYield"].toString());
      servingSize = num.parse(numString).toDouble();
    }
    if (jsonData.containsKey("recipeInstructions")) {
      for (int idx = 0; idx < jsonData["recipeInstructions"].length; idx++) {
        List<String> stepsProcessed =
            _processSteps(jsonData["recipeInstructions"][idx]);
        steps.addAll(stepsProcessed);
      }
    }
    processedJson.addAll({
      "title": jsonData["name"] ?? "",
      "description": jsonData["description"] ?? "",
      "totalTime": Conversion.prepTimeFromInt(totalTime),
      "serving size": servingSize ?? 0.0,
      "ingredients": jsonData["recipeIngredient"] ?? [],
      "steps": steps
    });
    return processedJson;
  }

  static List<String> _processSteps(Map<String, dynamic> instructionBlock) {
    List<String> steps = [];
    if (instructionBlock["@type"] == "HowToSection") {
      List<Map<String, dynamic>> stepList = instructionBlock["itemListElement"];
      stepList.forEach((Map<String, dynamic> stepInstruction) {
        if (stepInstruction["@type"] == "HowToStep") {
          steps.add(stepInstruction["text"]);
        }
      });
    } else if (instructionBlock["@type"] == "HowToStep") {
      steps.add(instructionBlock["text"]);
    }

    return steps;
  }

  static Future<Map<String, dynamic>> _processWebpage(
      String baseUrl, String route) async {
    try {
      WebScraper webScraper = WebScraper(baseUrl);
      try {
        if (await webScraper.loadWebPage(route)) {
          String pageContent = webScraper.getPageContent();
          for (RegExp regExp in _dataSchemes) {
            String jsonString = regExp.stringMatch(pageContent);
            var jsonData = json.decode(jsonString);
            if (jsonData is List) {
              return _reduceJson(jsonData);
            }
            if (jsonData != null && jsonData.toString().length > 0) {
              return jsonData;
            }
          }
          return {};
        }
      } catch (e) {
        CustomToast("Either recipe is not found or recipe data does not match allowed scheme.");
        return {};
      }
    } catch (e) {
      CustomToast("Webpage not found");
      return {};
    }
    return {};
  }

  static void _printLarge(String pageContent) {
    final pattern = RegExp('.{1,800}'); // 800 is the size of each chunk
    pattern.allMatches(pageContent).forEach((match) => print(match.group(0)));
  }

  static Map<String, dynamic> _reduceJson(List<dynamic> mapList) {
    var out = mapList.reduce((map1, map2) => map1..addAll(map2));
    return out;
  }

  static int _processTimeString(String time) {
    String timeStr = time.toLowerCase().trim();

    if (timeStr.startsWith("p")) {
      return _processPandasTimeString(timeStr);
    }
    return _processRegularTime(timeStr);
  }

  static int _processRegularTime(String timeString) {
    //Minutes Seconds hours days
    String timeStr = "";
    try {
      List<String> timeTokens = timeString.split(" ");
      for (String token in timeTokens) {
        print(token);
        if (token.startsWith("y"))
          timeStr = "$timeStr Years ";
        else if (token.startsWith("d"))
          timeStr = "$timeStr Days ";
        else if (token.startsWith("h"))
          timeStr = "$timeStr Hours ";
        else if (token.startsWith("m"))
          timeStr = "$timeStr Minutes ";
        else if (token.startsWith("s"))
          timeStr = "$timeStr Seconds ";
        else
          timeStr = '$timeStr $token';
      }
      timeStr = timeStr.replaceAll(RegExp(r"\s+"), " ").trim();
      if (timeStr.trim().length == 0) {
        timeStr = "0 Days 0 Hours 0 Minutes";
        return Conversion.prepTimeToInt(timeStr);
      }
      List<String> processedStr = timeStr.split(" ");
      print(processedStr);
      if (processedStr[1] == "Years") {
        processedStr.removeRange(0, 2);
      }
      if (processedStr.last == "Seconds") {
        int listLen = processedStr.length;
        processedStr.removeRange(listLen - 2, listLen);
      }
      if (processedStr.isEmpty || processedStr[1] != "Days") {
        processedStr.insert(0, "0");
        processedStr.insert(1, "Days");
      }
      if (processedStr.length == 2 || processedStr[3] != "Hours") {
        processedStr.insert(2, "0");
        processedStr.insert(3, "Hours");
      }
      if (processedStr.length == 4 || processedStr[5] != "Minutes") {
        processedStr.insert(4, "0");
        processedStr.insert(5, "Minutes");
      }
      print(processedStr);
      timeStr = processedStr.join(" ");
      return Conversion.prepTimeToInt(timeStr);
    } catch (e) {
      return 0;
    }
  }

  static int _processPandasTimeString(String timeString) {
    try {
      bool hasYear = timeString.contains("y");
      bool hasDays = timeString.contains("d");
      bool hasHours = timeString.contains("h");
      bool hasMin = timeString.contains("m");
      bool hasSec = timeString.contains("s");

      List<String> time = timeString
          .replaceAll(RegExp(r'[a-zA-Z]'), " ")
          .replaceAll(RegExp(r"\s+"), " ")
          .trim()
          .split(" ");

      // need string to be in this format: "0 Days 0 Hours 0 Minutes";
      if (hasYear) time.removeAt(0);
      if (hasSec) time.removeLast();

      if (hasDays)
        time.insert(1, "Days");
      else {
        time.insert(0, "0");
        time.insert(1, "Days");
      }
      if (hasHours) {
        time.insert(3, "Hours");
      } else {
        time.insert(2, "0");
        time.insert(3, "Hours");
      }
      if (hasMin) {
        time.insert(5, "Minutes");
      } else {
        time.insert(4, "0");
        time.insert(5, "Minutes");
      }
      String timeStr = time.join(" ");
      print(timeStr);

      return Conversion.prepTimeToInt(timeStr);
    } catch (e) {
      return 0;
    }
  }
}
