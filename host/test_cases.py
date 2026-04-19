import numpy as np


def make_identity_case(N):
    A = np.eye(N, dtype=np.int16)
    B = np.arange(1, N * N + 1, dtype=np.int16).reshape(N, N)
    expected = A.astype(np.int32) @ B.astype(np.int32)
    return "identity_times_known", A, B, expected


def make_zero_case(N):
    A = np.zeros((N, N), dtype=np.int16)
    B = np.arange(1, N * N + 1, dtype=np.int16).reshape(N, N)
    expected = A.astype(np.int32) @ B.astype(np.int32)
    return "zero_times_known", A, B, expected


def make_ones_case(N):
    A = np.ones((N, N), dtype=np.int16)
    B = np.ones((N, N), dtype=np.int16)
    expected = A.astype(np.int32) @ B.astype(np.int32)
    return "ones_times_ones", A, B, expected


def make_signed_case(N):
    vals = np.array([
        [-2, -1,  0,  1],
        [ 2, -2,  1,  0],
        [ 1,  3, -1, -2],
        [ 0,  1,  2, -3],
    ], dtype=np.int16)

    if N == 4:
        A = vals.copy()
        B = vals[::-1].copy()
    else:
        rng = np.random.default_rng(42)
        A = rng.integers(-3, 4, size=(N, N), dtype=np.int16)
        B = rng.integers(-3, 4, size=(N, N), dtype=np.int16)

    expected = A.astype(np.int32) @ B.astype(np.int32)
    return "mixed_signed", A, B, expected


def make_fixed_random_case(N, seed=42):
    import math

    rng = np.random.default_rng(seed)
    max_val = int(math.sqrt((2**31 - 1) / N)) - 1
    A = rng.integers(-max_val, max_val, size=(N, N)).astype(np.int16)
    B = rng.integers(-max_val, max_val, size=(N, N)).astype(np.int16)
    expected = A.astype(np.int32) @ B.astype(np.int32)
    return f"fixed_random_seed_{seed}", A, B, expected


            
def main():
    with open("test_cases_output.txt", "w") as f:
        for N in [4, 8]:
            f.write(f"\n{'='*60}\n")
            f.write(f"Test cases for N = {N}\n")
            f.write(f"{'='*60}\n")

            cases = [
                make_identity_case(N),
                make_zero_case(N),
                make_ones_case(N),
                make_signed_case(N),
                make_fixed_random_case(N, seed=42),
            ]

            for name, A, B, expected in cases:
                f.write(f"\nCase: {name}\n")
                f.write("A =\n")
                f.write(str(A) + "\n")
                f.write("B =\n")
                f.write(str(B) + "\n")
                f.write("Expected C =\n")
                f.write(str(expected) + "\n")

    print("Saved to test_cases_output.txt")            


if __name__ == "__main__":
    main()