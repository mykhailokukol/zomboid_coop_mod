# CO-OP — Project Zomboid mod (Build 42)

Co-op tools for a shared base: a shared checklist of skill books, magazines and VHS
tapes, map marks shared automatically, pings everyone can see, a shared to-do list, a
choice of where crafted and removed items land, an Organization skill that makes
containers hold more, and wear colours behind the hotbar.

Every feature has its own on/off switch in the sandbox options, so you can take only
the parts you want.

**[English](#english) · [Українська](#українська) · [Русский](#русский)**

---

## English

### What it does

- **Books at home** — a shared checklist of skill books, recipe magazines and
  skill-teaching VHS tapes. One player marks an item as "at home", everyone on the
  server sees it, with who marked it, when, and an optional note ("Rosewood, top shelf").
  Marked items get a **white check mark** in the inventory; read books keep the green one.
  Right-clicking a shelf or a crate in the world marks everything inside it at once,
  bags packed in it included.
- **Shared map marks** — an **MP** tick box on the map drawing panel, on by default.
  Everything you draw is shared with all players the moment you place it.
- **Pings** — press **Ping** (middle mouse by default) on the open map or anywhere in
  the world and everyone on the server sees the spot for a few seconds: a patch on the
  ground, an arrow at the edge of the screen pointing at it, your name above it and a
  line in chat. What was under the cursor picks the icon and the colour — a zombie, a
  player, a car, a body, loose loot, or a plain spot in your own colour.
- **Shared to-do list** — one list for the whole server in its own window on **[**.
  Anyone can add a line, tick it off, edit it or delete it, and every line remembers who
  wrote it and who finished it. Changes other people make are announced in chat, so the
  list gets noticed without anyone opening it.
- **Item output destination** — where new items go: your hands, your bags, a container
  next to you, or the ground. Cooking, carpentry, car mechanics and smithing each get
  their own setting, plus a default for everything else. Applies to crafting and to
  parts you take off a vehicle.
- **Organization skill** — a skill from 0 to 10 replacing the Organized / Disorganized
  traits. It raises the capacity of containers you organise (permanently, for everyone)
  and how fast you move items. Trained by the weight you move through storage.
- **Push a vehicle** — stand at the front or the back of a car or a trailer, press
  **V** and pick **Push**. How fast it rolls depends on what it weighs — up to 10 km/h
  for a trailer or a small car, 7 for an ordinary one, 4 for a van or a truck — and you
  go along with
  your hands on the bodywork until you press **Esc**. It will not budge a car somebody
  is sitting behind the wheel of, one with the engine running, or one missing a wheel;
  a burnt-out wreck is fair game.
- **Digging clay** — with a shovel on you, right-click the ground next to a river or a
  lake and pick **Dig for clay**. It digs like a garden plot — same effort, same noise —
  and gives you one to eleven lumps of clay depending on your Pottery, plus 10
  Pottery XP. A patch of bank you have dug gives nothing for a week, and everyone on
  the server shares that: two people cannot work the same spot twice.
- **Hotbar condition colours** — a hotbar slot holding a worn item gets its background
  split into a coloured column per state the item has: condition, head and sharpness,
  green above 75%, yellow down to 25%, red below. An item in good shape draws nothing,
  so the hotbar only lights up when something needs attention. Local only, nothing is
  sent anywhere.

### Requirements

Project Zomboid **Build 42**. Works in single player, in a hosted "My Server" game and
on a dedicated server.

### Install without the Steam Workshop

1. Download this repository — green **Code** button → **Download ZIP** — and unpack it.
   (Or `git clone https://github.com/mykhailokukol/zomboid_coop_mod.git`.)

2. Copy the **`CO-OP`** folder from `mods/` into your Project Zomboid user folder:

   | System | Path |
   |---|---|
   | Windows | `C:\Users\<you>\Zomboid\mods\` |
   | Linux | `~/Zomboid/mods/` |
   | macOS | `~/Zomboid/mods/` |

3. Check the result. `mod.info` must sit **inside** the `42` folder — that is what
   tells Build 42 the mod is for this build:

   ```
   Zomboid/mods/CO-OP/
   └── 42/
       ├── mod.info
       ├── poster.png
       └── media/
   ```

4. Start the game, open **MODS** in the main menu, tick **CO-OP**, press **DONE**.

5. Mods are remembered per save, so when you create or load a world, check
   **Choose Mods...** there too.

### Multiplayer

Everyone needs the same folder — the mod is not on the Workshop, so it cannot download
itself, and a player without it cannot join.

On a hosted server the mod must also be enabled **in the server settings**, not only in
your client mod list:

1. Main menu → **HOST** → **Manage settings...**
2. Pick your settings → **Edit Selected Settings**
3. Open the **Mods** group on the left
4. Under *Add an installed mod to the list*, choose **CO-OP**
5. Save, go back, **START**

That writes `Mods=CO-OP` into `Zomboid/Server/<name>.ini`, which you can also edit by
hand. For a dedicated server: put the folder in the server's `Zomboid/mods/`, add
`CO-OP` to the `Mods=` line, restart.

### Settings

Everything is in the sandbox options, on a **CO-OP** page of their own: in a solo game
on the world creation screen, on a server under **Manage settings... → Edit Selected
Settings**. There is an on/off switch per feature — switching one off leaves the vanilla
behaviour, not a half-working mod — plus how long a ping lives, the cooldown between two
pings from the same player, whether pings and to-do changes are announced in chat, the
Organization XP rate, how many lines the to-do list will hold, the three speeds a
vehicle can be pushed at, and how long a dug patch of riverbank takes to give clay again
(with the XP and the amount it gives).

Settings are read as they are used, so changing one on a running server reaches everyone
without a reload. Containers the Organization skill has already enlarged keep their size
if you switch it off later.

### Using it

| Feature | How |
|---|---|
| Mark a book | Right-click it → **Books at home** → *Mark as at home* |
| Mark a whole shelf | Right-click the shelf or crate in the world → *Mark all as at home* |
| Open the checklist | **K** (rebindable under Options → Keybindings, section *Books At Home*) |
| Share map marks | Open the map, keep the **MP** box ticked |
| Ping a spot | **Middle mouse** in the world or on the open map (rebindable under Options → Keybindings, section *CO-OP*) |
| Open the to-do list | **[** (same section) |
| Choose where items go | The drop-down under the **Craft** button, or under the part lists in the vehicle mechanics window |
| Organization skill | In the character skills panel, under Crafting |
| Push a vehicle | Stand at its front or back → **V** → *Push*. **Esc** to let go |
| Dig clay | Carry a shovel → right-click the ground within a tile of a river or lake → *Dig for clay* |
| Turn a feature off | Sandbox options → **CO-OP** |

### Updating

Replace the `CO-OP` folder with the new one and restart the game. On a server, restart
the server too — it runs its own copy of the mod.

### Uninstalling

Delete `Zomboid/mods/CO-OP`. Book marks and the to-do list live in the world save and
are simply ignored once the mod is gone.

---

## Українська

### Що це

- **Книги вдома** — спільний список книг навичок, журналів рецептів і касет, що вчать
  навичок. Один гравець позначає предмет як «вдома», і це бачать усі на сервері: хто
  позначив, коли, і необов'язкова нотатка («Роузвуд, верхня полиця»). Позначені
  предмети отримують **білу галочку** в інвентарі; прочитані книги залишають зелену.
  ПКМ по полиці чи ящику у світі позначає все, що всередині, разом із вкладеними
  сумками.
- **Спільні позначки на карті** — прапорець **MP** на панелі малювання карти, увімкнений
  за замовчуванням. Усе, що ви малюєте, одразу бачать усі гравці.
- **Мітки (пінги)** — натисніть **Мітка** (за замовчуванням середня кнопка миші) на
  відкритій карті або будь-де у світі, і всі на сервері кілька секунд бачать це місце:
  пляму на землі, стрілку з краю екрана, ваше ім'я над міткою та рядок у чаті. Те, що
  було під курсором, визначає значок і колір — зомбі, гравець, автівка, тіло, лут або
  просто місце вашим власним кольором.
- **Спільний список справ** — один список на весь сервер, в окремому вікні на **[**.
  Будь-хто може додати рядок, позначити виконаним, змінити чи видалити його; кожен рядок
  пам'ятає, хто його написав і хто його закрив. Про чужі зміни пишеться рядок у чаті,
  тож список помітний, навіть якщо ніхто не відкриває вікно.
- **Куди складати нові предмети** — у руки, у сумки, у контейнер поруч або на землю.
  Кулінарія, столярство, автомеханіка та ковальство мають власне налаштування, плюс
  типове для всього іншого. Діє і для крафту, і для знятих з машини деталей.
- **Навичка «Організація»** — навичка від 0 до 10, що замінює риси «Організований» /
  «Неорганізований». Збільшує місткість контейнерів, які ви впорядковуєте (назавжди, для
  всіх), і швидкість перекладання речей. Зростає від ваги, яку ви переносите крізь
  сховища.
- **Бетонозмішувач** — змішувач, що стоїть на будмайданчиках, у грі не робить нічого.
  Тепер його можна віднести додому (30 кг, і лише порожнім), лишити під дощем, щоб
  набрався води, зберігати в барабані до 30 кг речей і замісити глиняний цемент із того,
  що всередині — вода, глина, мішок піску або жмут трави та відро — в одному вікні.
- **Штовхати машину** — станьте спереду або ззаду автівки чи причепа, натисніть **V**
  і виберіть **Штовхати**. Швидкість залежить від ваги — до 10 км/год для причепа
  чи невеликої автівки, 7 для звичайної, 4 для фургона чи вантажівки — а ви йдете поряд,
  спершись на кузов, доки не натиснете **Esc**. Не зрушить автівку, за кермом якої хтось
  сидить, із запущеним двигуном або без колеса; згорілий каркас штовхати можна.
- **Копання глини** — маючи лопату, натисніть ПКМ по землі біля річки чи озера і
  виберіть **Копати глину**. Копається так само, як грядка — та сама втома, той самий
  шум — і дає від однієї до одинадцяти грудок глини залежно від гончарства, а також
  10 одиниць досвіду гончарства. Викопана ділянка берега тиждень нічого не дає, і це
  спільне для всього сервера: двоє не викопають одне й те саме місце двічі.
- **Смуги стану на панелі швидкого доступу** — комірка з надягнутим предметом ділить тло
  на кольорові смуги, по одній на кожен стан предмета: міцність, стан голівки та
  гострота, зелений понад 75%, жовтий до 25%, нижче червоний. Справний предмет не малює
  нічого, тож панель світиться лише тоді, коли щось потребує уваги. Суто локально,
  нікуди не передається.

### Вимоги

Project Zomboid **Build 42**. Працює в одиночній грі, на «своєму сервері» та на
виділеному сервері.

### Встановлення без Steam Workshop

1. Завантажте репозиторій — зелена кнопка **Code** → **Download ZIP** — і розпакуйте.
   (Або `git clone https://github.com/mykhailokukol/zomboid_coop_mod.git`.)

2. Скопіюйте теку **`CO-OP`** з `mods/` у теку користувача Project Zomboid:

   | Система | Шлях |
   |---|---|
   | Windows | `C:\Users\<ви>\Zomboid\mods\` |
   | Linux | `~/Zomboid/mods/` |
   | macOS | `~/Zomboid/mods/` |

3. Перевірте результат. `mod.info` має лежати **всередині** теки `42` — саме це каже
   Build 42, що мод для цієї версії:

   ```
   Zomboid/mods/CO-OP/
   └── 42/
       ├── mod.info
       ├── poster.png
       └── media/
   ```

4. Запустіть гру, у головному меню відкрийте **МОДИ**, увімкніть **CO-OP**, натисніть
   **ГОТОВО**.

5. Список модів зберігається для кожного світу окремо, тож під час створення або
   завантаження світу перевірте також **«Вибрати моди...»**.

### Мультиплеєр

Однакова тека потрібна всім — мода немає у Workshop, сам він не завантажиться, і без
нього гравець не зайде на сервер.

На своєму сервері мод треба увімкнути ще й **у налаштуваннях сервера**, а не лише в
клієнтському списку модів:

1. Головне меню → **СВІЙ СЕРВЕР** → **«Налаштування...»**
2. Виберіть налаштування → **«Редагувати вибрані налаштування»**
3. Зліва відкрийте групу **«Моди»**
4. У рядку *«Додати встановлений мод до списку»* виберіть **CO-OP**
5. Збережіть, поверніться, **ЗАПУСТИТИ**

Це запише `Mods=CO-OP` у `Zomboid/Server/<назва>.ini` — цей файл можна редагувати й
вручну. Для виділеного сервера: покладіть теку в `Zomboid/mods/` сервера, додайте
`CO-OP` до рядка `Mods=`, перезапустіть.

### Налаштування

Усе живе в пісочниці (sandbox), на власній сторінці **CO-OP**: в одиночній грі — на
екрані створення світу, на сервері — у **«Налаштування...» → «Редагувати вибрані
налаштування»**. Там є вимикач для кожної можливості (вимкнена можливість повертає
звичайну поведінку гри, а не половину мода), а також час життя мітки, затримка між
мітками одного гравця, оголошення міток і змін списку справ у чаті, швидкість досвіду
«Організації», межа довжини списку справ, три швидкості, з якими можна штовхати
машину, і час, за який викопана ділянка берега знову дає глину (разом із досвідом і
кількістю глини).

Налаштування читаються в момент використання, тож зміна на запущеному сервері доходить
до всіх без перезаходу. Контейнери, які «Організація» вже збільшила, зберігають свій
розмір, навіть якщо згодом її вимкнути.

### Як користуватися

| Можливість | Як |
|---|---|
| Позначити книгу | ПКМ по книзі → **Книги вдома** → *Позначити: вдома* |
| Позначити цілу полицю | ПКМ по полиці чи ящику у світі → *Позначити все як «вдома»* |
| Відкрити список книг | **K** (змінюється: Налаштування → Керування, розділ *Books At Home*) |
| Ділитися позначками карти | Відкрийте карту, залиште прапорець **MP** увімкненим |
| Поставити мітку | **Середня кнопка миші** у світі або на відкритій карті (змінюється: Налаштування → Керування, розділ *CO-OP*) |
| Відкрити список справ | **[** (той самий розділ) |
| Куди складати предмети | Випадний список під кнопкою **Створити** або під списками деталей у вікні механіки |
| Навичка «Організація» | У панелі навичок персонажа, у групі «Створення» |
| Користуватися бетонозмішувачем | ПКМ по ньому → **Бетонозмішувач** → *Відкрити* (або *Підняти*) |
| Штовхати машину | Станьте спереду чи ззаду → **V** → *Штовхати*. **Esc**, щоб відпустити |
| Копати глину | Візьміть лопату → ПКМ по землі за крок від річки чи озера → *Копати глину* |
| Вимкнути можливість | Налаштування пісочниці → **CO-OP** |

### Оновлення

Замініть теку `CO-OP` новою і перезапустіть гру. На сервері перезапустіть і сервер — він
використовує власну копію мода.

### Видалення

Видаліть `Zomboid/mods/CO-OP`. Позначки книг і список справ зберігаються у світі та
просто ігноруються без мода.

---

## Русский

### Что это

- **Книги дома** — общий список книг навыков, журналов рецептов и кассет, обучающих
  навыкам. Один игрок отмечает предмет как «дома», и это видят все на сервере: кто
  отметил, когда, и необязательная заметка («Роузвуд, верхняя полка»). Отмеченные
  предметы получают **белую галочку** в инвентаре; прочитанные книги сохраняют зелёную.
  ПКМ по полке или ящику в мире отмечает всё, что внутри, вместе с вложенными сумками.
- **Общие отметки на карте** — флажок **MP** на панели рисования карты, включён по
  умолчанию. Всё, что вы рисуете, сразу видят все игроки.
- **Метки (пинги)** — нажмите **Метка** (по умолчанию средняя кнопка мыши) на открытой
  карте или где угодно в мире, и все на сервере несколько секунд видят это место: пятно
  на земле, стрелку с края экрана, ваше имя над меткой и строку в чате. То, что было под
  курсором, задаёт значок и цвет — зомби, игрок, машина, тело, лут или просто место
  вашим собственным цветом.
- **Общий список дел** — один список на весь сервер, в отдельном окне на **[**. Любой
  может добавить строку, отметить её выполненной, изменить или удалить; каждая строка
  помнит, кто её написал и кто её закрыл. О чужих изменениях пишется строка в чате,
  поэтому список заметен, даже если никто не открывает окно.
- **Куда складывать новые предметы** — в руки, в сумки, в контейнер рядом или на землю.
  У кулинарии, столярки, автомеханики и кузнечного дела своя настройка, плюс общая для
  всего остального. Работает и для крафта, и для снятых с машины деталей.
- **Навык «Организация»** — навык от 0 до 10, заменяющий черты «Организованный» /
  «Неорганизованный». Увеличивает вместимость контейнеров, которые вы разбираете
  (навсегда, для всех), и скорость перекладывания вещей. Растёт от веса, который вы
  переносите через хранилища.
- **Бетономешалка** — мешалка, стоящая на стройках, в игре не делает ничего. Теперь её
  можно унести домой (30 кг, и только пустой), оставить под дождём, чтобы набралась вода,
  хранить в барабане до 30 кг вещей и замешать глиняный цемент из того, что внутри —
  вода, глина, мешок песка или пучок травы и ведро — в одном окне.
- **Толкать машину** — встаньте спереди или сзади автомобиля либо прицепа, нажмите
  **V** и выберите **Толкать**. Скорость зависит от веса — до 10 км/ч для прицепа
  или небольшой машины, 7 для обычной, 4 для фургона или грузовика — а вы идёте рядом,
  упершись в кузов, пока не нажмёте **Esc**. Не сдвинет машину, за рулём которой кто-то
  сидит, с заведённым двигателем или без колеса; сгоревший остов толкать можно.
- **Копание глины** — с лопатой в сумке нажмите ПКМ по земле у реки или озера и
  выберите **Копать глину**. Копается так же, как грядка — та же усталость, тот же шум —
  и даёт от одной до одиннадцати горстей глины в зависимости от гончарного дела, плюс
  10 единиц опыта гончарного дела. Выкопанный участок берега неделю ничего не даёт, и
  это общее для всего сервера: двое не выкопают одно и то же место дважды.
- **Полосы состояния на панели быстрого доступа** — ячейка с надетым предметом делит фон
  на цветные полосы, по одной на каждое состояние предмета: прочность, состояние головки
  и заточка, зелёный выше 75%, жёлтый до 25%, ниже красный. Исправный предмет не рисует
  ничего, поэтому панель светится только тогда, когда что-то требует внимания. Чисто
  локально, никуда не передаётся.

### Требования

Project Zomboid **Build 42**. Работает в одиночной игре, на «своём сервере» и на
выделенном сервере.

### Установка без Steam Workshop

1. Скачайте репозиторий — зелёная кнопка **Code** → **Download ZIP** — и распакуйте.
   (Или `git clone https://github.com/mykhailokukol/zomboid_coop_mod.git`.)

2. Скопируйте папку **`CO-OP`** из `mods/` в пользовательскую папку Project Zomboid:

   | Система | Путь |
   |---|---|
   | Windows | `C:\Users\<вы>\Zomboid\mods\` |
   | Linux | `~/Zomboid/mods/` |
   | macOS | `~/Zomboid/mods/` |

3. Проверьте результат. `mod.info` должен лежать **внутри** папки `42` — именно это
   говорит Build 42, что мод для этой версии:

   ```
   Zomboid/mods/CO-OP/
   └── 42/
       ├── mod.info
       ├── poster.png
       └── media/
   ```

4. Запустите игру, в главном меню откройте **МОДЫ**, включите **CO-OP**, нажмите
   **ГОТОВО**.

5. Список модов сохраняется для каждого мира отдельно, поэтому при создании или
   загрузке мира проверьте также **«Выбрать моды...»**.

### Мультиплеер

Одинаковая папка нужна всем — мода нет в Workshop, сам он не скачается, и без него
игрок не зайдёт на сервер.

На своём сервере мод нужно включить ещё и **в настройках сервера**, а не только в
клиентском списке модов:

1. Главное меню → **СВОЙ СЕРВЕР** → **«Настройка...»**
2. Выберите настройки → **«Редактировать выбранные настройки»**
3. Слева откройте группу **«Моды»**
4. В строке *«Добавить установленный мод в список»* выберите **CO-OP**
5. Сохраните, вернитесь, **ЗАПУСТИТЬ**

Это запишет `Mods=CO-OP` в `Zomboid/Server/<имя>.ini` — этот файл можно править и
вручную. Для выделенного сервера: положите папку в `Zomboid/mods/` сервера, добавьте
`CO-OP` в строку `Mods=`, перезапустите.

### Настройки

Всё находится в песочнице (sandbox), на отдельной странице **CO-OP**: в одиночной игре —
на экране создания мира, на сервере — в **«Настройка...» → «Редактировать выбранные
настройки»**. Там есть выключатель для каждой возможности (выключенная возвращает
обычное поведение игры, а не половину мода), а также время жизни метки, задержка между
метками одного игрока, объявление меток и изменений списка дел в чате, скорость опыта
«Организации», предел длины списка дел, три скорости, с которыми можно толкать
машину, и время, за которое выкопанный участок берега снова даёт глину (вместе с опытом
и количеством глины).

Настройки читаются в момент использования, поэтому изменение на запущенном сервере
доходит до всех без перезахода. Контейнеры, которые «Организация» уже увеличила,
сохраняют свой размер, даже если потом её выключить.

### Как пользоваться

| Возможность | Как |
|---|---|
| Отметить книгу | ПКМ по книге → **Книги дома** → *Отметить: дома* |
| Отметить целую полку | ПКМ по полке или ящику в мире → *Отметить всё как «дома»* |
| Открыть список книг | **K** (меняется: Настройки → Управление, раздел *Books At Home*) |
| Делиться отметками карты | Откройте карту, оставьте флажок **MP** включённым |
| Поставить метку | **Средняя кнопка мыши** в мире или на открытой карте (меняется: Настройки → Управление, раздел *CO-OP*) |
| Открыть список дел | **[** (тот же раздел) |
| Куда складывать предметы | Выпадающий список под кнопкой **Создать** или под списками деталей в окне механики |
| Навык «Организация» | В панели навыков персонажа, в группе «Создание» |
| Пользоваться бетономешалкой | ПКМ по ней → **Бетономешалка** → *Открыть* (или *Поднять*) |
| Толкать машину | Встаньте спереди или сзади → **V** → *Толкать*. **Esc**, чтобы отпустить |
| Копать глину | Возьмите лопату → ПКМ по земле в шаге от реки или озера → *Копать глину* |
| Выключить возможность | Настройки песочницы → **CO-OP** |

### Обновление

Замените папку `CO-OP` новой и перезапустите игру. На сервере перезапустите и сервер —
он использует свою копию мода.

### Удаление

Удалите `Zomboid/mods/CO-OP`. Отметки книг и список дел хранятся в мире и просто
игнорируются без мода.
