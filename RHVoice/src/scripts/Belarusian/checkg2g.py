import textdistance
from collections import defaultdict

def check_g2g(file_path):
    good_pairs = []
    bad_pairs = []
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]
    for i in range(0, len(lines) - 1, 2):
        word1, word2 = lines[i], lines[i + 1]
        similarity = textdistance.hamming.normalized_similarity(word1, word2)
        if similarity > 0.7:
            good_pairs.append(word1)
        else:
            bad_pairs.append(word1)
            print(f"Line {i+1}: Mismatch: unstressed word {word1.replace(" ","")} with alleged stressed word {word2.replace(" ","")} ({similarity:.2f}% similar)")
    return len(good_pairs), len(bad_pairs)

def check_for_homographs(file_path):
	homographs = defaultdict(set)
	multiple = []
	with open(file_path, 'r', encoding='utf-8') as f:
		lines = [line.strip() for line in f if line.strip()]
	for i in range(0, len(lines) - 1, 2):
		word1, word2 = lines[i], lines[i + 1]
		homographs[word1].add(word2)
	for word, stressed_words in homographs.items():
		if len(stressed_words) > 1:
			multiple.append(f"{word}|{', '.join(stressed_words)}")
	return multiple

def remove_duplicates(file_path, converted_path):
	cleandict = []
	duplicates = []
	with open(file_path, 'r', encoding='utf-8') as fin:
		lines = [line.strip() for line in fin if line.strip()]
	for i in range(0, len(lines) - 1, 2):
		word1, word2 = lines[i], lines[i + 1]
		if word1 == word2:
			duplicates.append(word1)
		else:
			cleandict.append(word1)
			cleandict.append(word2)
	with open(converted_path, 'w', encoding='utf-8') as fout:
		fout.write("\n".join(cleandict))
	return duplicates, len(duplicates)

# These are the examples we ran to fix the Belarussian stressing dictionary during development.
#good, bad = check_g2g("bel.txt")
#print(f"Good words: {good}\nBad words: {bad}")
with open("bel_homographs.csv", "w", encoding="utf-8") as out:
	out.write("original spaced word|spaced homograph separated by commas (multiple entries of the original word)\n")
	out.write('\n'.join(check_for_homographs("bel.txt")))
#print("Working...")
#doubles, numdoubles = remove_duplicates("bel.txt", "belnew.txt")
#print(f"Done! We removed {numdoubles} doubles, which are words with no replacement.")