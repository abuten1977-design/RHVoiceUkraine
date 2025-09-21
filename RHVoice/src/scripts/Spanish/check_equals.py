# Copyright (C) 2024  Mateo Cedillo <angelitomateocedillo@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 2.1 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.

# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

import difflib

with open("checktrans-output - copia.txt", "r") as f:
    text1 = f.readlines()
with open("checktrans-output.txt", "r") as f2:
    text2 = f2.readlines()

if len(text1) != len(text2):
    raise ValueError("No hay cómo hacer la diferencia!")

for i, (line1, line2) in enumerate(zip(text1, text2), start=1):
    ratio = difflib.SequenceMatcher(None, line1, line2).ratio()
    print(f"Línea {i} similitud: {ratio:.2f}")
    if ratio < 1.0:
        print(f"Copia: {line1}")
        print(f"Actual: {line2}")
print("Listo, patrón.")