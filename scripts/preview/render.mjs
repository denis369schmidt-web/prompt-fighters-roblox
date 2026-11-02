// Renders a scene exported by scripts/export-scene.luau to a PNG with three.js in headless Chromium.
// An approximation of Roblox's look for quick visual checks and previews, not a pixel match:
// parts, neon glow (bloom), sky by time of day, fog, SurfaceGui text.
//
//   node render.mjs <scene.json> <out.png> [--eye x,y,z] [--look x,y,z] [--fov 40] [--size 1280x720]

import { chromium } from "playwright";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const option = (name, fallback) => {
	const i = args.indexOf(`--${name}`);
	return i >= 0 ? args[i + 1] : fallback;
};
const vec = (text) => text.split(",").map(Number);

const [scenePath, outPath] = args;
const [width, height] = option("size", "1280x720").split("x").map(Number);
const view = {
	eye: vec(option("eye", "0,72,52")),
	look: vec(option("look", "0,64,0")),
	fov: Number(option("fov", "40")),
};

const three = pathToFileURL(join(here, "node_modules/three/build/three.module.js")).href;
const addons = pathToFileURL(join(here, "node_modules/three/examples/jsm/")).href;
const scene = readFileSync(scenePath, "utf8");

const html = `<!doctype html><html><head><style>html,body{margin:0;background:#000}</style>
<script type="importmap">{"imports":{"three":"${three}","three/addons/":"${addons}"}}</script></head>
<body><script type="module">
import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";

const data = ${scene};
const view = ${JSON.stringify(view)};
const W = ${width}, H = ${height};
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setSize(W, H);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
document.body.appendChild(renderer.domElement);

const L = data.lighting;
const day = L.clock > 6 && L.clock < 18.2;
const dusk = day && L.clock > 16.5;
renderer.toneMappingExposure = Math.pow(2, L.exposure || 0) * (day ? 1.0 : 1.15);

const scene = new THREE.Scene();
// Sky: vertical gradient on a big sphere.
const top = new THREE.Color(day ? (dusk ? 0x3a6db0 : 0x4a8fe0) : 0x05040f);
const bottom = new THREE.Color(day ? (dusk ? 0xf0a868 : 0xbfe0ff) : 0x2a1a52);
const skyGeo = new THREE.SphereGeometry(4000, 32, 16);
const skyMat = new THREE.ShaderMaterial({
	side: THREE.BackSide, depthWrite: false,
	uniforms: { top: { value: top }, bottom: { value: bottom } },
	vertexShader: "varying vec3 p; void main(){ p = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }",
	fragmentShader: "uniform vec3 top; uniform vec3 bottom; varying vec3 p; void main(){ float t = clamp(p.y*1.6+0.25,0.0,1.0); gl_FragColor = vec4(mix(bottom, top, t),1.0); }",
});
scene.add(new THREE.Mesh(skyGeo, skyMat));
if (L.fog && L.density > 0) {
	const fog = new THREE.Color(...L.fog).lerp(bottom, 0.4);
	scene.fog = new THREE.Fog(fog, 120, 120 + 900 * Math.max(0.15, 1 - L.density * 2.5));
}

const amb = new THREE.Color(...L.ambient);
scene.add(new THREE.HemisphereLight(amb.clone().lerp(new THREE.Color(1, 1, 1), 0.3), amb.clone().multiplyScalar(0.35), day ? 1.6 : 1.4));
const sun = new THREE.DirectionalLight(day ? (dusk ? 0xffc890 : 0xfff4e0) : 0x9fb0ff, day ? 2.2 : 0.7);
sun.position.set(-60, 160, 120);
sun.target.position.set(0, 60, 0);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -140, right: 140, top: 140, bottom: -140, near: 10, far: 600 });
scene.add(sun, sun.target);
// Fill light from the camera side (the game's key lights).
const fill = new THREE.PointLight(0xe8e4ff, 2.5, 160, 0.6);
fill.position.set(view.eye[0], view.eye[1] + 10, view.eye[2] - 10);
scene.add(fill);

const MAT = {
	Metal: { roughness: 0.35, metalness: 0.65 }, DiamondPlate: { roughness: 0.4, metalness: 0.6 },
	CorrodedMetal: { roughness: 0.8, metalness: 0.4 }, Glass: { roughness: 0.05, metalness: 0.1, glass: true },
	Ice: { roughness: 0.1, metalness: 0.05, glass: true }, SmoothPlastic: { roughness: 0.45 },
	Marble: { roughness: 0.3 }, Slate: { roughness: 0.85 }, Concrete: { roughness: 0.95 },
	Wood: { roughness: 0.8 }, WoodPlanks: { roughness: 0.8 }, Fabric: { roughness: 1 },
	Sand: { roughness: 1 }, Sandstone: { roughness: 0.95 }, Snow: { roughness: 1 }, Grass: { roughness: 1 },
	Rock: { roughness: 1 }, Cobblestone: { roughness: 0.95 }, Brick: { roughness: 0.95 }, Asphalt: { roughness: 0.9 },
	Ground: { roughness: 1 }, Basalt: { roughness: 0.9 }, Leather: { roughness: 0.7 }, ForceField: { roughness: 0.2, glass: true },
};

function wedgeGeometry(x, y, z) {
	// Roblox wedge: tall face at +Z, slope falling toward -Z.
	const shape = new THREE.Shape();
	shape.moveTo(-z / 2, -y / 2); shape.lineTo(z / 2, -y / 2); shape.lineTo(z / 2, y / 2); shape.closePath();
	const g = new THREE.ExtrudeGeometry(shape, { depth: x, bevelEnabled: false });
	g.translate(0, 0, -x / 2);
	g.rotateY(-Math.PI / 2); // extrusion axis -> X, shape x -> Z
	return g;
}

function textTexture(part, texts, sx, sy) {
	const ppu = 32;
	const canvas = document.createElement("canvas");
	canvas.width = Math.min(2048, Math.max(64, Math.round(sx * ppu)));
	canvas.height = Math.min(2048, Math.max(32, Math.round(sy * ppu)));
	const ctx = canvas.getContext("2d");
	// A see-through part (floor text) only shows its letters.
	if (part.transparency < 0.95) {
		ctx.fillStyle = "rgb(" + part.color.map((c) => Math.round(c * 255)).join(",") + ")";
		ctx.fillRect(0, 0, canvas.width, canvas.height);
	}
	for (const t of texts) {
		const [px, py, bw, bh] = t.box;
		const x = px * canvas.width, y = py * canvas.height, w = bw * canvas.width, h = bh * canvas.height;
		let size = h * 0.85;
		ctx.font = "900 " + size + "px Arial Black, Arial, sans-serif";
		while (ctx.measureText(t.text).width > w * 0.95 && size > 6) {
			size -= 1;
			ctx.font = "900 " + size + "px Arial Black, Arial, sans-serif";
		}
		ctx.fillStyle = "rgb(" + t.color.map((c) => Math.round(c * 255)).join(",") + ")";
		ctx.textAlign = "center";
		ctx.textBaseline = "middle";
		ctx.fillText(t.text, x + w / 2, y + h / 2);
	}
	const tex = new THREE.CanvasTexture(canvas);
	tex.colorSpace = THREE.SRGBColorSpace;
	return tex;
}

const geoCache = new Map();
for (const p of data.parts) {
	const [x, y, z] = p.size;
	let geo;
	const key = p.shape + p.size.join(",");
	if (geoCache.has(key)) geo = geoCache.get(key);
	else {
		if (p.shape === "Ball") geo = new THREE.SphereGeometry(Math.min(x, y, z) / 2, 24, 16);
		else if (p.shape === "Cylinder") { geo = new THREE.CylinderGeometry(Math.min(y, z) / 2, Math.min(y, z) / 2, x, 28); geo.rotateZ(Math.PI / 2); }
		else if (p.shape === "Wedge") geo = wedgeGeometry(x, y, z);
		else geo = new THREE.BoxGeometry(x, y, z);
		geoCache.set(key, geo);
	}
	const color = new THREE.Color().setRGB(...p.color, THREE.SRGBColorSpace);
	const opacity = 1 - p.transparency;
	let mat;
	if (p.material === "Neon") {
		mat = new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(2.2), transparent: opacity < 1, opacity, fog: true });
	} else {
		const m = MAT[p.material] || { roughness: 0.6 };
		mat = new THREE.MeshStandardMaterial({
			color, roughness: m.roughness, metalness: m.metalness || 0,
			transparent: opacity < 1 || !!m.glass, opacity: m.glass ? Math.min(opacity, 0.55) : opacity,
		});
	}
	const mesh = new THREE.Mesh(geo, mat);
	const c = p.cf;
	const matrix = new THREE.Matrix4().set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
	mesh.matrixAutoUpdate = false;
	mesh.matrix.copy(matrix);
	mesh.castShadow = p.material !== "Neon" && opacity > 0.5 && Math.max(x, y, z) < 120;
	mesh.receiveShadow = true;
	scene.add(mesh);
	if (p.texts) {
		// One plane per face that carries text (Front = -Z, Back = +Z, Top = +Y with the text's top toward -Z).
		const faces = {};
		for (const t of p.texts) (faces[t.face] = faces[t.face] || []).push(t);
		for (const [face, texts] of Object.entries(faces)) {
			const top = face === "Top";
			const [w, h] = top ? [x, z] : [x, y];
			const tex = textTexture(p, texts, w, h);
			const plane = new THREE.Mesh(new THREE.PlaneGeometry(w, h),
				new THREE.MeshBasicMaterial({ map: tex, toneMapped: false, transparent: p.transparency >= 0.95 }));
			if (top) { plane.position.set(0, y / 2 + 0.02, 0); plane.rotation.x = -Math.PI / 2; }
			else if (face === "Back") plane.position.set(0, 0, z / 2 + 0.02);
			else { plane.position.set(0, 0, -(z / 2 + 0.02)); plane.rotation.y = Math.PI; }
			mesh.add(plane);
			plane.updateMatrix();
		}
	}
}

const camera = new THREE.PerspectiveCamera(view.fov, W / H, 0.5, 8000);
camera.position.set(...view.eye);
camera.lookAt(...view.look);
const composer = new EffectComposer(renderer);
composer.addPass(new RenderPass(scene, camera));
composer.addPass(new UnrealBloomPass(new THREE.Vector2(W, H), day ? 0.45 : 0.8, 0.5, 0.82));
composer.addPass(new OutputPass());
composer.render();
window.done = true;
</script></body></html>`;

const dir = mkdtempSync(join(tmpdir(), "pf-preview-"));
const page = join(dir, "scene.html");
writeFileSync(page, html);
const browser = await chromium.launch({
	executablePath: process.env.CHROMIUM_PATH || undefined,
	args: ["--use-gl=angle", "--use-angle=swiftshader", "--allow-file-access-from-files"] });
const tab = await browser.newPage({ viewport: { width, height } });
tab.on("pageerror", (e) => console.error("page error:", e.message));
tab.on("console", (m) => m.type() === "error" && console.error("console:", m.text()));
await tab.goto(pathToFileURL(page).href);
await tab.waitForFunction(() => window.done === true, null, { timeout: 120000 });
await tab.locator("canvas").screenshot({ path: resolve(outPath) });
await browser.close();
console.log(`rendered ${scenePath} -> ${outPath}`);
