// SymmetricEigen — dense symmetric eigendecomposition via LAPACK ssyev (Accelerate).
//
// SECDET Stage B. The McFee/Ellis pipeline needs the bottom-k eigenvectors of the
// normalized Laplacian (a real symmetric matrix). LAPACK `ssyev` returns ALL
// eigenpairs in ascending eigenvalue order — we keep the lowest k. First LAPACK
// use in this codebase; vDSP has no symmetric eigensolver.

import Accelerate
import Foundation

// MARK: - SymmetricEigen

enum SymmetricEigen {

    /// Eigendecomposition of a real symmetric `size × size` matrix.
    ///
    /// - Parameters:
    ///   - matrix: Row-major `size × size` symmetric matrix (length `size*size`). For a
    ///     symmetric matrix the row-major and column-major layouts are identical,
    ///     so it is passed to LAPACK unchanged.
    ///   - size: Dimension.
    /// - Returns: `eigenvalues` ascending (length `size`) and `eigenvectors`
    ///   row-major `size × size` with `eigenvectors[i*size + j]` = component `i` of the
    ///   `j`-th eigenvector (matches scipy.linalg.eigh's `ev[:, j]`). Returns nil
    ///   if LAPACK reports failure.
    static func decompose(matrix: [Float], size: Int) -> (eigenvalues: [Float], eigenvectors: [Float])? {
        guard size > 0, matrix.count == size * size else { return nil }

        // ponytail: classic CLAPACK ssyev_ (Int32 args) — deprecated since macOS
        // 13.3 but functional; the deprecation warning is non-fatal (SPM compiles
        // the engine with -suppress-warnings for the app, and the engine target is
        // not warnings-as-errors). Upgrade path if it ever needs to be clean:
        // build the DSP target with -Xcc -DACCELERATE_NEW_LAPACK and switch the
        // Int32s to __LAPACK_int.
        var jobz = Int8(UInt8(ascii: "V"))      // eigenvalues + eigenvectors
        // Input is symmetric (RecurrenceGraph symmetrizes the Laplacian), so the
        // triangle is immaterial and row-major == column-major.
        var uplo = Int8(UInt8(ascii: "U"))
        var order = Int32(size)
        var lda = Int32(size)
        var info = Int32(0)
        // ssyev overwrites the input with the eigenvectors (column-major).
        var work = matrix
        var eigenvalues = [Float](repeating: 0, count: size)

        // Workspace query (lwork = -1) → optimal size in queryWork[0].
        var lwork = Int32(-1)
        var queryWork = [Float](repeating: 0, count: 1)
        ssyev_(&jobz, &uplo, &order, &work, &lda, &eigenvalues, &queryWork, &lwork, &info)
        guard info == 0 else { return nil }

        lwork = Int32(max(1, Int(queryWork[0])))
        var workspace = [Float](repeating: 0, count: Int(lwork))
        ssyev_(&jobz, &uplo, &order, &work, &lda, &eigenvalues, &workspace, &lwork, &info)
        guard info == 0 else { return nil }

        // `work` now holds eigenvectors column-major: column j (a[j*size + i]) is the
        // j-th eigenvector. Transpose into row-major so [i*size + j] = component i of
        // eigenvector j (scipy ev[:, j] convention).
        var eigenvectors = [Float](repeating: 0, count: size * size)
        for j in 0..<size {
            for i in 0..<size {
                eigenvectors[i * size + j] = work[j * size + i]
            }
        }
        return (eigenvalues, eigenvectors)
    }
}
