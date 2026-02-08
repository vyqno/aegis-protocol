import { createThirdwebClient } from "thirdweb";

// Use a dummy clientId during build/SSR, real one at runtime
const clientId = process.env.NEXT_PUBLIC_THIRDWEB_CLIENT_ID || "build-placeholder";

export const client = createThirdwebClient({
  clientId,
});
