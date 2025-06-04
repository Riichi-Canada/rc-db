This is a guide on what numbers to use when putting data in CSV format.

# Event CSV
Filename should be something like `toronto_riichi_open_2025.csv`.

## event_code
If you don't have direct access to the database, just use a placeholder for this one (for now).

## player_id
Again, use a placeholder. Most importantly, **ONLY SPECIFY AN ID FOR CANADIAN PLAYERS**.

# Event results csv
Filename should be something like `toronto_riichi_open_2025_results.csv`.

## event_region
Use the following for reference:
* [Québec map](https://www.cartograf.fr/img/quebec/carte_regions_quebec.jpg)
* [Ontario map](https://forms.mgcs.gov.on.ca/en/dataset/cd7b542d-0491-4271-b6cf-2eb5efe0f744/resource/8a8dad5c-783f-48be-8243-b10680f2ad22/download/6_fcgp_2024-25_map_of_ontario-regions_en.pdf)
* [British Columbia map](https://maps-vancouver.com/british-columbia-regions-map)


- **1:** Québec (Greater Montreal)
- **2:** Québec (Capitale-Nationale—Chaudière-Appalaches)
- **3:** Québec (Outaouais)
- **4:** Québec (Montérégie—Estrie—Centre-du-Québec)
- **5:** Québec (Laurentides—Lanaudière—Mauricie)
- **6:** Québec (Saguenay—Lac-Saint-Jean)
- **7:** Québec (Bas-Saint-Laurent—Gaspésie)
- **8:** Québec (Abitibi-Témiscamingue)
- **9:** Québec (Côte-Nord—Nord-du-Québec)
- **10:** Ontario (Central)
- **11:** Ontario (East)
- **12:** Ontario (West)
- **13:** Ontario (North)
- **14:** British Columbia (South West—Vancouver Island)
- **15:** British Columbia (South Central—South East)
- **16:** British Columbia (North)
- **17:** Nova Scotia
- **18:** New Brunswick
- **19:** Prince Edward Island
- **20:** Newfoundland and Labrador
- **21:** Manitoba
- **22:** Saskatchewan
- **23:** Alberta
- **24:** Northwest Territories
- **25:** Yukon
- **26:** Nunavut
- **27:** United States
- **28:** Europe
- **29:** Japan
- **30:** Asia
- **31:** Oceania
- **32:** South America
- **33:** Other

## event_type
- **1:** Tournament
- **2:** League (CWL)
- **3:** IORMC Qualifier

If you find an event that doesn't fit any of these, please let me know.

## event_ruleset
- **1:** Unknown
- **2:** EMA 2008
- **3:** EMA 2012
- **4:** EMA 2016
- **5:** EMA 2025
- **6:** WRC 2014
- **7:** WRC 2017
- **8:** WRC 2022
- **9:** WRC 2025
- **10:** Saikouisen
- **11:** Other
