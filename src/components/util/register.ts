import { initReactI18next } from "react-i18next";
import i18n from "i18next";

import en from "@/translations/en.json";
import pl from "@/translations/pl.json";

const isGoogleBot = navigator.userAgent.includes("Googlebot");

i18n.use(initReactI18next).init({
    resources: {
        en,
        pl,
    },
    lng: isGoogleBot ? "pl" : localStorage.getItem("language") || navigator.language.split("-")[0],
    fallbackLng: "pl",
});

const envApiBase = import.meta.env.VITE_API_BASE;
const envCloudBase = import.meta.env.VITE_CLOUD_API_BASE;

window.Gay = {
    base: envApiBase || "https://api.zbiorkom.live",
    cloudBase: envCloudBase || "https://4.zbiorkom.live",
};

console.log(
    "%czbiorkom.live",
    "font-size: 64px; color: #276b2b; font-weight: bold; text-shadow: 0 0 10px #276b2b;",
);
