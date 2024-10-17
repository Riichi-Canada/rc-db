# Schéma BD

## Quel est l'objectif?
On veut créer un site semblable à celui de l'EMA (European Mahjong Association) pour consigner les résultats des tournois et autres événements compétitifs, et le classement des joueurs de Mahjong (Riichi) au Canada. Plus particulièrement, on veut **trois** pages principales:

### Résultats par compétition
- Affiche les résultats d'un tournoi ou d'une ligue.
- Tous les tournois dans lesquels des joueurs Canadiens ont participé devront se retrouver sur le site, même s'ils n'ont pas eu lieu au Canada. Vu qu'on aura forcément beaucoup de tournois Américains dans les données, il se peut qu'on décide un jour d'étendre le site au Riichi compétitif partout en Amérique du Nord plutôt que juste au Canada.
- Le cas d'utilisation **crucial** est l'ajout de tournois aux données, qui doit être aussi facile que possible. Une idée serait d'avoir un format fixe (encore indéterminé mais probablement un CSV formaté d'une certaine façon) qui peut être importé et auto-remplir à peu près tout.
- Voici ce qu'on veut faire, presque exactement: http://mahjong-europe.org/ranking/Tournament/TR_RCR_350.html

### Résultats par joueur
- Affiche une liste des compétitions auxquelles la personne a participé, ainsi que les points donnés par chaque résultat.
- Pour calculer la valeur en points d'un événement compétitif, on doit impérativement connaître les variables suivantes:
    - Dates de début/fin
    - En personne vs en ligne
    - Région (pour savoir si c'est hors-région)
    - Position et nombre de joueurs (ex. 7e/32)
- Ces données devraient être remplies automatiquement lors de l'ajout des résultats d'un événement compétitif dans les données. En particulier, je ne sais pas si c'est possible de faire ça 100% automatique, mais ça ferait bien si on pouvait trouver automatiquement les joueurs existants, et créer automatiquement les joueurs qui ne sont pas encore présents dans les données (ou au moins avoir un genre de prompt pour rentrer les données que le système peut pas connaître juste avec les résultats du tournoi)
- Voici ce qu'on veut faire, presque exactement: http://mahjong-europe.org/ranking/Players/04160071.html

### Classement des joueurs
- Affiche une liste des joueurs classés et leur pointage actuel.
- Voici ce qu'on veut faire, presque exactement: http://mahjong-europe.org/ranking/rcr.html

## Tables

### `event_types`
Types d'événements. Servira à les séparer sur le site.
- Deux types possibles: Tournoi et Ligue. D'autres types pourront être rajoutés plus tard peut-être? Mais c'est surtout ces deux-là.
- Pour l'instant, le calcul des points par événement ne change pas selon le type... mais rien ne garantit que ce sera toujours le cas.
- Chaque événement compétitif a un type.

```sql
CREATE TABLE IF NOT EXISTS event_types (
    format TEXT PRIMARY KEY
);

INSERT INTO event_types
VALUES('Tournament', 'League');
```

### `regions`
Régions. Chaque événement a une région et chaque compétiteur a une région, car lors du calcul du score global d'un compétiteur, il est important de savoir si un événement est hors-région ou non. Cette valeur ne sera pas nécessairement visible par les utilisateurs, c'est à priori pour usage interne lors das calculs.

La liste des régions dans l'exemple suivant n'est pas nécessairement exhaustive. Ça ne risque pas de changer de manière significative, mais on se sait jamais.

```sql
CREATE TABLE IF NOT EXISTS regions (
    region TEXT PRIMARY KEY
);

INSERT INTO regions
VALUES('Québec', 'Ontario', 'Canadian Prairies', 'Western Canada', 'Atlantic Canada', 'United States', 'Europe', 'Asia', 'Oceania', 'South America', 'Other');
```

### `events`
Événements compétitifs. Doit contenir les champs suivants:
- id (duh)
- Nom de l'événement (ex. "Montréal Riichi Open 2024")
- Région de l'événement (ex. "Québec")
- Type de l'événement (ex. "Tournament")
- Date de début (ex. 2024-06-01)
- Date de fin (ex. 2024-06-02)
    - C'est important de connaître les dates pour déterminer la validité des événements lors du calcul des points d'un joueur.
- Ville (ex. "Montréal")
- Pays (ex. "Canada")
- Nombre de joueurs (ex. 32)
- En ligne? (bool) (important pour le calcul des points)

On fait également le lien avec les tables `regions` et `event_types`.

```sql
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_name TEXT NOT NULL,
    event_region TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_start_date DATE NOT NULL,
    event_end_date DATE NOT NULL,
    event_city TEXT NOT NULL,
    event_country TEXT NOT NULL,
    number_of_players INTEGER NOT NULL,
    is_online BOOLEAN NOT NULL,
    FOREIGN KEY (event_region) REFERENCES regions(region)
    FOREIGN KEY (event_type) REFERENCES event_types(event_type)
);
```

### `players`
Compétiteurs. Doit contenir les champs suivants:
- id (duh)
- Prénom (ex. "Loïc")
- Nom de famille (ex. "Roberge")
- Région (ex. "Québec")

```sql
CREATE TABLE IF NOT EXISTS players (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    player_region TEXT NOT NULL,
    FOREIGN KEY (player_region) REFERENCES regions(region),
);
```

### `event_results`
Résultats des compétitions. J'ai cru que la meilleure manière de procéder serait d'avoir un champ par position par tournoi; par exemple, un tournoi de 32 personnes aurait 32 champs dans la table. Dans cette optique, la table doit contenir les champs suivants:
- id de l'événement
- id du joueur
- Prénom du joueur
- Nom du joueur
- Position

```sql
CREATE TABLE IF NOT EXISTS event_results (
    event_id INTEGER,
    player_id INTEGER,
    player_first_name TEXT NOT NULL,
    player_last_name TEXT NOT NULL,
    placement INTEGER NOT NULL,
    -- PRIMARY KEY (event_id, player_id),
    FOREIGN KEY (event_id) REFERENCES events(id),
    FOREIGN KEY (player_id) REFERENCES players(player_id)
);
```

### `clubs`
Clubs de Mahjong. Moins crucial que le reste, sert surtout à afficher l'appartenance à un club sur la page des joueurs. Plus tard il y aura peut-être un lien vers les sites des clubs qui en ont, des trucs du genre.

Tel qu'expliqué précédemment, tant qu'à avoir les données de joueurs Américains dans certains tournois, on va probablement s'en servir plus tard (ce n'est pas une priorité de le faire tout de suite), donc des clubs Américains se retrouveront sûrement dans cette liste plus tard.

```sql
CREATE TABLE IF NOT EXISTS clubs (
    id INTEGER PRIMARY KEY,
    club_name TEXT NOT NULL
);

INSERT INTO clubs(id, club_name)
VALUES
    (1, 'Club Riichi de Montréal'),
    (2, 'Toronto Riichi Club'),
    (3, 'Gatineau-Ottawa Riichi'),
    (4, 'University of British Columbia Mahjong Club');
```

### `club_affiliations`
Je me souviens plus pourquoi j'ai fait ça, est-ce que ça vous semble pertinent?

```sql
CREATE TABLE IF NOT EXISTS club_affiliations (
    club_id INTEGER,
    player_id INTEGER,
    -- PRIMARY KEY (club_id, player_id),
    FOREIGN KEY (club_id) REFERENCES clubs(id),
    FOREIGN KEY (player_id) REFERENCES players(player_id)
)
```