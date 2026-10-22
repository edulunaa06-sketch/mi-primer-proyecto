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
F={f[0]:f for f in foods}
out={"version":1,
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
json.dump(out,open(sys.argv[1],'w'),ensure_ascii=False,indent=1)
