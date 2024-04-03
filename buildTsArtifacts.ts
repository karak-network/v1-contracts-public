import fs from "fs";
import path from "path";

const TS_ARTIFACTS_DIR = `ts-artifacts`;
const OUT_DIR = "out";
const INDEX_FILE = `index.ts`;

const CONTRACTS_TO_IGNORE: RegExp[] = [
    /draft-.*\.sol/,
    /TetherLikeToken\.sol/,
    /console\.sol/,
    /console2\.sol/,
    /safeconsole\.sol/,
    /test\.sol/,
    /.*\.t\.sol/,
    /Std.*\.sol/,
    /AttackVectors\.sol/,
    /matchUtils\.sol/,
    /setupUtils\.sol/,
    /signUtils\.sol/,
    /Vm\.sol/,
    /Base\.sol/,
    /IERC165\.sol/,
    /IERC721\.sol/,
    /Counter\.s\.sol/,
    /MockERC20\.sol/,
    /MockERC721\.sol/,
    /Script\.sol/,
    /Test\.sol/,
];

interface ArtifactOutputMap {
    [key: string]: string;
}

export async function main() {
    const contracts = await fs.promises.readdir(path.resolve(OUT_DIR));
    const artifactOutputMap: ArtifactOutputMap = {};
    if (fs.existsSync(TS_ARTIFACTS_DIR)) {
        await fs.promises.rm(TS_ARTIFACTS_DIR, { recursive: true });
    }
    await fs.promises.mkdir(TS_ARTIFACTS_DIR);

    if (fs.existsSync(INDEX_FILE)) {
        await fs.promises.rm(INDEX_FILE);
    }
    await fs.promises.writeFile(INDEX_FILE, "");

    for (const contract of contracts) {
        if (CONTRACTS_TO_IGNORE.some((pattern) => pattern.test(contract))) {
            continue;
        }
        const contractArtifacts = await fs.promises.readdir(
            path.resolve(OUT_DIR, contract)
        );
        for (const artifact of contractArtifacts) {
            let inputDataPath = `${OUT_DIR}/${contract}/${artifact}`;
            console.log(`Converting ${inputDataPath}`);
            const [artifactName] = artifact.split(".");
            if(!artifactName) continue;
            if (fs.lstatSync(inputDataPath).isDirectory()) {
                inputDataPath = inputDataPath + `/${artifactName}.json`;
            }
    
            try {
                const jsonData = require(path.resolve(inputDataPath));    
    
                const outputDir = `${TS_ARTIFACTS_DIR}/${contract}`;
    
                if (!fs.existsSync(outputDir)) {
                    await fs.promises.mkdir(path.resolve(outputDir));
                }
    
                const artifactOutputFile = `${outputDir}/${artifactName}`;
                await fs.promises.writeFile(
                    path.resolve(`${artifactOutputFile}.ts`),
                    `export const ${artifactName} = ${JSON.stringify(jsonData, null, 2)} as const;`
                );
    
                // Check if an export statement for the current artifact already exists
                artifactOutputMap[artifactName] = `export { ${artifactName} } from "./${artifactOutputFile}";\n`;
                
            } catch (error) {
                console.info(`Error converting ${inputDataPath}: ${error}`)
            }
        }
    }

    // Write the index file
    for (const artifact in artifactOutputMap) {
        await fs.promises.appendFile(INDEX_FILE, artifactOutputMap[artifact]!);
    }
}

if (require.main === module) {
    main();
}
