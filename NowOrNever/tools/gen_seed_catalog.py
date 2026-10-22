import json, sys
SRC="Valor de referencia aproximado (tablas generales tipo USDA FoodData Central/BEDCA). Verifica con la etiqueta de tu producto."
LBL="Depende mucho de la marca: copia los valores de la etiqueta de tu producto."
foods = [
 # key, name, kcal, P, C, F, basis, provisional, note
 ("chicken_breast","Pechuga de pollo",120,22.5,0,2.6,"raw",False,SRC),
 ("turkey_breast","Pechuga de pavo",114,23.7,0,1.5,"raw",True,SRC),
 ("lean_beef","Ternera picada magra (5 % grasa)",137,21.4,0,5.0,"raw",False,SRC),
 ("salmon","Salmón",208,20.4,0,13.4,"raw",False,SRC),
 ("cod","Bacalao fresco",82,17.8,0,0.7,"raw",False,SRC),
 ("tuna_drained","Atún al natural",116,25.5,0,0.8,"drained",False,SRC),
 ("egg","Huevo entero (sin cáscara)",143,12.6,0.7,9.5,"edible",False,SRC),
 ("egg_white","Clara de huevo",52,10.9,0.7,0.2,"raw",False,SRC),
 ("rice","Arroz blanco",360,6.5,79.3,0.6,"dry",False,SRC),
 ("pasta","Pasta de trigo",371,13.0,74.7,1.5,"dry",False,SRC),
 ("oats","Copos de avena",389,16.9,66.3,6.9,"dry",False,SRC),
 ("quinoa","Quinoa",368,14.1,64.2,6.1,"dry",False,SRC),
 ("bread_ww","Pan integral",252,12.4,42.7,3.5,"asWeighed",True,LBL),
 ("rice_cakes","Tortitas de arroz",387,8.2,81.5,2.8,"asWeighed",True,LBL),
 ("potato","Patata (pelada)",77,2.0,17.5,0.1,"raw",False,SRC),
 ("sweet_potato","Boniato (pelado)",86,1.6,20.1,0.1,"raw",False,SRC),
 ("chickpeas","Garbanzos",164,8.9,27.4,2.6,"cookedDrained",True,SRC+" Si son de bote, usa la etiqueta."),
 ("lentils","Lentejas",116,9.0,20.1,0.4,"cookedDrained",True,SRC+" Si son de bote, usa la etiqueta."),
 ("greek_yogurt","Yogur griego natural 0 %",59,10.2,3.6,0.4,"asWeighed",True,LBL),
 ("skyr","Skyr natural",63,11.0,4.0,0.2,"asWeighed",True,LBL),
 ("milk_semi","Leche semidesnatada",46,3.4,4.8,1.6,"asWeighed",True,LBL),
 ("whey","Proteína whey (en polvo)",400,80.0,8.0,6.0,"asWeighed",True,LBL),
 ("banana","Plátano",89,1.1,22.8,0.3,"edible",False,SRC),
 ("apple","Manzana",52,0.3,13.8,0.2,"edible",False,SRC),
 ("blueberries","Arándanos",57,0.7,14.5,0.3,"edible",False,SRC),
 ("olive_oil","Aceite de oliva",884,0,0,100,"asWeighed",False,SRC),
 ("avocado","Aguacate",160,2.0,8.5,14.7,"edible",False,SRC),
 ("walnuts","Nueces (peladas)",654,15.2,13.7,65.2,"edible",False,SRC),
 ("peanut_butter","Crema de cacahuete 100 %",588,25.0,20.0,50.0,"asWeighed",True,LBL),
 ("broccoli","Brócoli",34,2.8,6.6,0.4,"raw",False,SRC),
 ("mixed_veg","Verduras variadas (genérico)",30,1.5,5.0,0.3,"raw",True,"Valor genérico orientativo: las calorías reales dependen de las verduras concretas. Sustitúyelo por alimentos específicos."),
 ("tomato","Tomate",18,0.9,3.9,0.2,"raw",False,SRC),
 ("lettuce","Lechuga",15,1.4,2.9,0.2,"raw",False,SRC),
 ("zucchini","Calabacín",17,1.2,3.1,0.3,"raw",False,SRC),
 ("red_pepper","Pimiento rojo",31,1.0,6.0,0.3,"raw",False,SRC),
 ("honey","Miel",304,0.3,82.4,0,"asWeighed",False,SRC),
 # --- Versión 2: alimentos para la biblioteca de ideas ---
 ("strawberries","Fresas",32,0.7,7.7,0.3,"edible",False,SRC),
 ("kiwi","Kiwi",61,1.1,14.7,0.5,"edible",False,SRC),
 ("orange","Naranja",47,0.9,11.8,0.1,"edible",False,SRC),
 ("pineapple","Piña",50,0.5,13.1,0.1,"edible",False,SRC),
 ("mango","Mango",60,0.8,15.0,0.4,"edible",False,SRC),
 ("almonds","Almendras",579,21.2,21.6,49.9,"edible",False,SRC),
 ("turkey_cold","Fiambre de pechuga de pavo (≥90 % carne)",100,19.0,2.0,1.5,"asWeighed",True,LBL),
 ("serrano","Jamón serrano",241,30.5,0.5,13.0,"asWeighed",True,LBL),
 ("bread_white","Pan blanco (barra)",266,8.9,49.2,3.3,"asWeighed",True,LBL),
 ("cooked_ham","Jamón cocido extra",110,19.0,1.5,3.0,"asWeighed",True,LBL),
 ("fresh_cheese","Queso fresco batido 0 %",46,8.0,3.5,0.2,"asWeighed",True,LBL),
 ("tortilla_ww","Tortilla de trigo integral",300,9.0,50.0,7.0,"asWeighed",True,LBL),
 ("hummus","Hummus",166,7.9,14.3,9.6,"asWeighed",True,LBL),
 ("smoked_salmon","Salmón ahumado",117,18.3,0,4.3,"asWeighed",True,LBL),
 ("shrimp","Gambas peladas",85,20.1,0,0.5,"raw",False,SRC),
 ("tofu","Tofu firme",144,17.3,2.8,8.7,"asWeighed",True,LBL),
 ("pork_loin","Lomo de cerdo (cinta)",143,21.0,0,6.0,"raw",True,SRC),
 ("chicken_thigh","Contramuslo de pollo sin piel",121,19.7,0,4.1,"raw",True,SRC),
 ("sardines","Sardinas en conserva",208,24.6,0,11.5,"drained",True,LBL),
 ("couscous","Cuscús",376,12.8,77.4,0.6,"dry",False,SRC),
 ("mushrooms","Champiñones",22,3.1,3.3,0.3,"raw",False,SRC),
 ("spinach","Espinacas",23,2.9,3.6,0.4,"raw",False,SRC),
 ("onion","Cebolla",40,1.1,9.3,0.1,"raw",False,SRC),
 ("carrot","Zanahoria",41,0.9,9.6,0.2,"raw",False,SRC),
 ("cucumber","Pepino",15,0.7,3.6,0.1,"raw",False,SRC),
 ("peas","Guisantes",81,5.4,14.5,0.4,"raw",False,SRC),
 ("green_beans","Judías verdes",31,1.8,7.0,0.2,"raw",False,SRC),
]
B,L,S,D="breakfast","lunch","snack","dinner"
menus = [
 ("Clásico pollo y salmón", {
   B:[("oats",70),("milk_semi",250),("whey",30),("banana",120)],
   L:[("chicken_breast",180),("rice",90),("mixed_veg",200),("olive_oil",10)],
   S:[("greek_yogurt",250),("walnuts",15),("blueberries",100)],
   D:[("salmon",150),("potato",300),("broccoli",200),("olive_oil",5)]}),
 ("Pasta y bacalao", {
   B:[("bread_ww",100),("egg",120),("egg_white",150),("tomato",100),("olive_oil",5)],
   L:[("lean_beef",170),("pasta",90),("tomato",150),("olive_oil",10)],
   S:[("skyr",200),("whey",20),("banana",120),("walnuts",15)],
   D:[("cod",250),("sweet_potato",300),("zucchini",200),("olive_oil",10)]}),
 ("Legumbres", {
   B:[("oats",80),("milk_semi",250),("whey",30),("blueberries",100)],
   L:[("chicken_breast",150),("chickpeas",200),("red_pepper",100),("olive_oil",10)],
   S:[("rice_cakes",30),("tuna_drained",120),("apple",150),("walnuts",15)],
   D:[("turkey_breast",160),("lentils",200),("mixed_veg",200),("olive_oil",10)]}),
 ("Arroz y ternera", {
   B:[("greek_yogurt",250),("oats",60),("whey",25),("banana",120)],
   L:[("lean_beef",180),("rice",90),("broccoli",200),("olive_oil",10)],
   S:[("bread_ww",60),("tuna_drained",100),("tomato",100),("avocado",60)],
   D:[("chicken_breast",200),("potato",300),("lettuce",100),("olive_oil",15)]}),
 ("Quinoa y pavo", {
   B:[("bread_ww",90),("egg",120),("egg_white",100),("avocado",50)],
   L:[("turkey_breast",200),("quinoa",90),("mixed_veg",200),("olive_oil",5)],
   S:[("skyr",250),("whey",20),("banana",120)],
   D:[("salmon",150),("rice",80),("zucchini",200),("olive_oil",5)]}),
 ("Pescado blanco", {
   B:[("oats",80),("milk_semi",250),("whey",30),("banana",120)],
   L:[("cod",250),("rice",90),("red_pepper",150),("avocado",50),("olive_oil",10)],
   S:[("greek_yogurt",250),("honey",15),("walnuts",20)],
   D:[("chicken_breast",180),("sweet_potato",250),("broccoli",200),("olive_oil",10)]}),
 ("Batido y pasta", {
   B:[("milk_semi",300),("whey",35),("oats",70),("peanut_butter",20),("banana",100)],
   L:[("chicken_breast",180),("pasta",90),("tomato",150),("olive_oil",10)],
   S:[("rice_cakes",30),("skyr",150),("blueberries",100)],
   D:[("tuna_drained",150),("potato",300),("egg",60),("lettuce",100),("olive_oil",10)]}),
 ("Huevos y ternera", {
   B:[("egg",120),("egg_white",200),("bread_ww",90),("tomato",100)],
   L:[("lean_beef",180),("potato",350),("mixed_veg",200),("olive_oil",10)],
   S:[("greek_yogurt",250),("oats",40),("whey",20),("apple",150),("walnuts",15)],
   D:[("cod",250),("rice",70),("zucchini",200),("olive_oil",10)]}),
 ("Día de carrera (más carbohidrato)", {
   B:[("oats",90),("milk_semi",250),("whey",30),("banana",120),("honey",10)],
   L:[("chicken_breast",180),("rice",100),("mixed_veg",150),("olive_oil",5)],
   S:[("rice_cakes",40),("skyr",200),("blueberries",100)],
   D:[("salmon",150),("pasta",70),("broccoli",150),("olive_oil",5)]}),
]
# Biblioteca de ideas: comidas sueltas con pesos exactos para elegir y combinar.
ideas = [
 (B,"Plato de frutas con yogur",[("banana",120),("strawberries",150),("kiwi",100),("pineapple",150),("greek_yogurt",150),("walnuts",10)]),
 (B,"Tostadas con aguacate y huevos",[("bread_ww",80),("avocado",60),("egg",120),("tomato",80)]),
 (B,"Yogur griego con avena y frutos rojos",[("greek_yogurt",250),("oats",40),("blueberries",100),("honey",10)]),
 (B,"Tortitas de avena y claras",[("oats",60),("egg_white",200),("banana",100),("peanut_butter",10)]),
 (B,"Tostadas con pavo y queso fresco",[("bread_ww",90),("turkey_cold",80),("fresh_cheese",100),("tomato",80)]),
 (B,"Batido de proteína, plátano y avena",[("milk_semi",300),("whey",30),("banana",120),("oats",40)]),
 (B,"Skyr con mango y almendras",[("skyr",250),("mango",120),("almonds",15)]),
 (B,"Tostadas con salmón ahumado",[("bread_ww",80),("smoked_salmon",70),("fresh_cheese",60),("avocado",40)]),
 (B,"Huevos revueltos con espinacas",[("egg",120),("egg_white",100),("spinach",60),("bread_ww",60),("olive_oil",3)]),
 (B,"Pan blanco con jamón serrano y tomate",[("bread_white",100),("serrano",50),("tomato",60),("olive_oil",5)]),
 (B,"Pan blanco con jamón cocido y café con leche",[("bread_white",90),("cooked_ham",80),("milk_semi",200)]),
 (B,"Tortitas de arroz con crema de cacahuete",[("rice_cakes",30),("peanut_butter",20),("banana",120),("milk_semi",250)]),
 (L,"Pollo salteado con arroz y verduras",[("chicken_breast",170),("rice",80),("red_pepper",100),("onion",50),("olive_oil",10)]),
 (L,"Macarrones con ternera y tomate",[("pasta",90),("lean_beef",130),("tomato",150),("onion",40),("olive_oil",5)]),
 (L,"Lentejas con verduras y huevo",[("lentils",250),("carrot",80),("onion",50),("egg",60),("olive_oil",10)]),
 (L,"Wrap de pollo y aguacate",[("tortilla_ww",80),("chicken_breast",150),("red_pepper",80),("lettuce",40),("avocado",50)]),
 (L,"Salmón con patata y judías verdes",[("salmon",150),("potato",250),("green_beans",150),("olive_oil",5)]),
 (L,"Ensalada de garbanzos con atún",[("chickpeas",200),("tuna_drained",120),("tomato",150),("cucumber",100),("olive_oil",10)]),
 (L,"Pavo con cuscús y calabacín",[("turkey_breast",180),("couscous",80),("zucchini",150),("olive_oil",10)]),
 (L,"Gambas salteadas con arroz y guisantes",[("shrimp",200),("rice",90),("peas",80),("olive_oil",10)]),
 (L,"Lomo de cerdo con boniato y brócoli",[("pork_loin",170),("sweet_potato",250),("broccoli",150),("olive_oil",5)]),
 (L,"Pasta con atún y tomate",[("pasta",90),("tuna_drained",120),("tomato",150),("olive_oil",5)]),
 (L,"Hamburguesa casera de ternera con patata",[("lean_beef",170),("potato",250),("lettuce",50),("tomato",80),("olive_oil",5)]),
 (L,"Tofu salteado con quinoa",[("tofu",200),("quinoa",70),("mushrooms",100),("spinach",80),("olive_oil",10)]),
 (S,"Yogur griego con nueces",[("greek_yogurt",200),("walnuts",15)]),
 (S,"Queso fresco batido con fresas",[("fresh_cheese",200),("strawberries",150),("honey",5)]),
 (S,"Hummus con zanahoria y pan",[("hummus",60),("carrot",100),("bread_ww",40)]),
 (S,"Bocadillo de pavo",[("bread_ww",60),("turkey_cold",60)]),
 (S,"Batido de proteína y plátano",[("whey",30),("milk_semi",250),("banana",100)]),
 (S,"Tortitas de arroz con jamón",[("rice_cakes",30),("serrano",40)]),
 (S,"Manzana con crema de cacahuete",[("apple",180),("peanut_butter",15)]),
 (S,"Bocadillo de jamón serrano",[("bread_white",60),("serrano",35)]),
 (S,"Skyr con kiwi",[("skyr",200),("kiwi",100)]),
 (D,"Tortilla francesa con ensalada",[("egg",180),("lettuce",80),("tomato",120),("bread_ww",40),("olive_oil",5)]),
 (D,"Bacalao al horno con verduras",[("cod",250),("zucchini",150),("red_pepper",100),("potato",150),("olive_oil",10)]),
 (D,"Ensalada de pollo con aguacate",[("chicken_breast",150),("lettuce",100),("tomato",150),("avocado",60),("olive_oil",5)]),
 (D,"Revuelto de gambas y champiñones",[("egg",120),("shrimp",120),("mushrooms",150),("olive_oil",5),("bread_ww",40)]),
 (D,"Salmón con brócoli y quinoa",[("salmon",150),("broccoli",200),("quinoa",40)]),
 (D,"Crema de calabacín con pavo",[("zucchini",300),("potato",100),("turkey_breast",150),("olive_oil",10)]),
 (D,"Wrap de atún y queso fresco",[("tortilla_ww",60),("tuna_drained",120),("lettuce",50),("tomato",80),("fresh_cheese",50)]),
 (D,"Sardinas con ensalada y patata",[("sardines",100),("lettuce",80),("tomato",120),("potato",150)]),
 (D,"Contramuslos al horno con verduras",[("chicken_thigh",180),("onion",80),("red_pepper",100),("zucchini",150),("olive_oil",10)]),
 (D,"Sándwich de jamón cocido, huevo y ensalada",[("bread_white",80),("cooked_ham",60),("egg",60),("lettuce",40),("tomato",80)]),
 (D,"Tofu con verduras y arroz",[("tofu",150),("broccoli",150),("carrot",80),("rice",50),("olive_oil",5)]),
]
F={f[0]:f for f in foods}
out={"version":3,
 "disclaimer":"Catálogo y menús de EJEMPLO con valores aproximados por 100 g. No son un plan nutricional calculado clínicamente. Revisa y edita cada alimento con la etiqueta de tu producto o una base de datos fiable.",
 "foods":[{"key":k,"name":n,"kcal":kc,"protein":p,"carbs":c,"fat":f,"basis":b,"provisional":pr,"macrosKnown":True,"source":s} for (k,n,kc,p,c,f,b,pr,s) in foods],
 "menus":[]}
tot_all=[]
for i,(name,meals) in enumerate(menus,1):
  m={"number":i,"name":name,"note":"Menú de ejemplo. Ajusta gramos y alimentos a tus necesidades.","meals":[]}
  T=[0,0,0,0]
  for t in (B,L,S,D):
    items=meals[t]
    for k,g in items:
      assert k in F,k
      f=F[k]
      for j in range(4): T[j]+=f[2+j]*g/100
    m["meals"].append({"type":t,"items":[{"food":k,"grams":g} for k,g in items]})
  out["menus"].append(m)
  print(f"{i} {name:38s} kcal {T[0]:6.0f} P {T[1]:5.1f} C {T[2]:5.1f} G {T[3]:5.1f}")
out["ideas"]=[]
counts={}
for t,name,items in ideas:
  T=[0,0,0,0]
  for k,g in items:
    assert k in F,k
    for j in range(4): T[j]+=F[k][2+j]*g/100
  counts[t]=counts.get(t,0)+1
  out["ideas"].append({"type":t,"name":name,"items":[{"food":k,"grams":g} for k,g in items]})
  print(f"  idea {t:9s} {name:42s} kcal {T[0]:5.0f} P {T[1]:5.1f} C {T[2]:5.1f} G {T[3]:5.1f}")
print(counts)
json.dump(out,open(sys.argv[1],'w'),ensure_ascii=False,indent=1)
