import 'dart:convert';

import 'package:mybmr/services/conversion.dart';
import 'package:mybmr/services/toast.dart';
import 'package:web_scraper/web_scraper.dart';

class RecipeScraper {
  /*
  * RecipeScraper should parse web data of approved recipe sits and return
  * title, description, servings, total time, ingredients and instructions
  * */

  static String websiteBaseUrl = "";
  static final List<RegExp> _dataSchemes = [
    RegExp(r'(?<=type="application/ld\+json">)(.*?)(?=</script>)',
        multiLine: true, dotAll: true),
  ];

  static const List<String> supportedSchemes = [
    "https://",
    "https://www.",
    "http://",
    "http://www.",
    ""
  ];
  static const List<String> supportedUrls = [
    "allrecipes.com/",
    "simplyrecipes.com/",
    "yummly.com/",
    "101cookbooks.com/",
    "bbc.co.uk/",
    "bbcgoodfood.com/",
    "bonappetit.com/",
    "closetcooking.com/",
    "cookstr.com/",
    "epicurious.com/",
    "foodrepublic.com/",
    "jamieoliver.com/",
    "mybakingaddiction.com/",
    "paninihappy.com/",
    "realsimple.com/",
    "steamykitchen.com/",
    "tastykitchen.com/",
    "thevintagemixer.com/",
    "twopeasandtheirpod.com/",
    "whatsgabycooking.com/"
  ];

  static bool isValidUrl(String inputUrl) {
    print(inputUrl);
    for (String baseUrl in supportedUrls) {
      for (String scheme in supportedSchemes) {
        String urlChoice = scheme + baseUrl;

        if (inputUrl.startsWith(urlChoice)) {
          websiteBaseUrl = urlChoice;
          return true;
        }
      }
    }
    return false;
  }

  static Future<Map<String, dynamic>> scrapeUrl(String inputUrl) async {
    Map<String, dynamic> jsonData =
        await _processWebpage(websiteBaseUrl, inputUrl);

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
    return _prepareData(jsonData);
  }

  static Map<String, dynamic> _prepareData(Map<String, dynamic> jsonData) {
    Map<String, dynamic> processedJson = {};
    int totalTime = 0;
    double servingSize = 0;
    List<String> steps = [];
    if (jsonData.containsKey("totalTime")) {
      totalTime = _processPandasTimeString(jsonData["totalTime"]);
    } else {
      if (jsonData.containsKey("cookTime"))
        totalTime += _processPandasTimeString(jsonData["cookTime"]);
      if (jsonData.containsKey("prepTime"))
        totalTime += _processPandasTimeString(jsonData["prepTime"]);
    }
    if (jsonData.containsKey("recipeYield")) {
      RegExp regex = RegExp(r'([\+\-]*\d*\.*\d+)');
      String numString = regex.stringMatch(jsonData["recipeYield"].toString());
      servingSize = num.parse(numString).toDouble();
    }

    for (int idx = 0; idx < jsonData["recipeInstructions"].length; idx++) {
      List<String> stepsProcessed = _processSteps(jsonData["recipeInstructions"][idx]);
      steps.addAll(stepsProcessed);
    }
    processedJson.addAll({
      "title": jsonData["name"],
      "description": jsonData["description"],
      "totalTime": Conversion.prepTimeFromInt(totalTime),
      "serving size": servingSize,
      "ingredients": jsonData["recipeIngredient"],
      "steps": steps
    });
    print(processedJson);
    return processedJson;
  }

  static List<String> _processSteps(Map<String, dynamic> instructionBlock) {
    List<String> steps = [];
    if (instructionBlock["@type"] == "HowToSection") {
      List<Map<String,dynamic>> stepList = instructionBlock["itemListElement"];
      stepList.forEach((Map<String,dynamic> stepInstruction) {
        if(stepInstruction["@type"] == "HowToStep"){
          steps.add(stepInstruction["text"]);
        }
      });

    } else if (instructionBlock["@type"] == "HowToStep") {
      steps.add(instructionBlock["text"]);
    }

    return steps;
  }

  static Future<Map<String, dynamic>> _processWebpage(
      String baseUrl, String fullPath) async {
    String route = fullPath.substring(baseUrl.length);
    print(baseUrl);
    print(route);
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
        CustomToast("Either recipe is not found or is un-serializable.");
        return {};
      }
    } catch (e) {
      CustomToast("Webpage not found");
      return {};
    }
    return {};
  }

  static void _printLarge(String pageContent) {
    /*
    * helpful when trying to print page contents of html document
    */
    final pattern = RegExp('.{1,500}'); 
    pattern.allMatches(pageContent).forEach((match) => print(match.group(0)));
  }

  static Map<String, dynamic> _reduceJson(List<dynamic> mapList) {
    var out = mapList.reduce((map1, map2) => map1..addAll(map2));
    return out;
  }

  static int _processPandasTimeString(String timeString) {
    bool hasYear = timeString.contains("Y");
    bool hasDays = timeString.contains("D");
    bool hasHours = timeString.contains("H");
    bool hasMin = timeString.contains("M");
    bool hasSec = timeString.contains("S");

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
    //OF FORM: 0 Days 0 Hours 0 Minutes
    return timeStr;
  }
}
