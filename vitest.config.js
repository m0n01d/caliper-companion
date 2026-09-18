import { defineConfig } from 'vitest/config'

// Unit tests are written in ReScript (src/**/*Test.res) and run on the
// compiled JS, as the spec asks. ReScript module names cannot contain dots,
// so the compiled test files are *Test.res.mjs rather than *.test.mjs.
export default defineConfig({
  test: {
    include: ['src/**/*Test.res.mjs'],
    environment: 'node',
    coverage: {
      provider: 'v8',
      include: ['src/core/**/*.res.mjs'],
      exclude: ['src/core/**/*Test.res.mjs', 'src/core/tests/**'],
      reporter: ['text', 'text-summary'],
    },
  },
})
