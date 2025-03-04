IDENTIFICATION DIVISION.
PROGRAM-ID. READ-MNIST.
ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT TRAIN-FILE ASSIGN TO 'mnist/mnist_train.csv'
        ORGANIZATION IS LINE SEQUENTIAL
        ACCESS MODE IS SEQUENTIAL.
    SELECT TEST-FILE ASSIGN TO 'mnist/mnist_test.csv'
        ORGANIZATION IS LINE SEQUENTIAL
        ACCESS MODE IS SEQUENTIAL.

DATA DIVISION.
FILE SECTION.
    FD TRAIN-FILE.
        01 TRAIN-RECORD        PIC X(8000).
    FD TEST-FILE.
        01 TEST-RECORD         PIC X(8000).

WORKING-STORAGE SECTION.
    01 EOF-FLAG              PIC X VALUE 'N'.
       88 END-OF-FILE        VALUE 'Y'.
    01 TRAIN-EOF-FLAG        PIC X VALUE 'N'.
       88 TRAIN-END-OF-FILE  VALUE 'Y'.
    01 TEST-EOF-FLAG         PIC X VALUE 'N'.
       88 TEST-END-OF-FILE   VALUE 'Y'.

    01 INPUT-RECORD          PIC X(8000).  *> Generic record for processing
    01 DATA-TYPE             PIC X(5).     *> "TRAIN" or "TEST"
    01 RECORD-COUNT          PIC 9(6) VALUE ZEROES.
    01 TRAIN-COUNT           PIC 9(6) VALUE ZEROES.
    01 TEST-COUNT            PIC 9(6) VALUE ZEROES.
    01 FIELD-COUNTER         PIC 9(4) VALUE 0.
    01 PIXEL-VALUE           PIC 9(3) VALUE 0.       *> Raw integer value (0-255)
    01 NORMALIZED-PIXEL      PIC 9V9(3) VALUE 0.     *> Normalized value (0.000-1.000)
    01 THE-LABEL             PIC 9(1) VALUE 0.
    01 FIELD-DATA            PIC X(3).
    01 DELIM-PTR             PIC 9(4) VALUE 1.
    01 START-PTR             PIC 9(4) VALUE 1.
    01 TEMP-LEN              PIC 9(4).
    01 CURRENT-IMAGE         PIC 9(5) VALUE 0.
    01 EPOCH                 PIC 9(2) VALUE 0.



    01 IMAGE-ARRAY-TRAIN.
       05 IMAGE OCCURS 60000 TIMES INDEXED BY TRAIN-INDEX.
          10 IMAGE-LABEL        PIC 9(1).
          10 PIX OCCURS 784 TIMES INDEXED BY PIXEL-INDEX
             PIC 9V9(3) VALUE 0.
    01 IMAGE-ARRAY-TEST.
       05 IMAGE-TEST OCCURS 10000 TIMES INDEXED BY TEST-INDEX.
          10 IMAGE-LABEL-TEST   PIC 9(1).
          10 PIX-TEST OCCURS 784 TIMES INDEXED BY PIXEL-INDEX
             PIC 9V9(3) VALUE 0.

    01 NEURAL-NETWORK.
      05 WEIGHT-IH OCCURS 784 TIMES.
           10 W-IH-COL OCCURS 10 TIMES USAGE COMP-1.
      05 BIAS-H OCCURS 10 TIMES USAGE COMP-1.
      05 WEIGHT-HO OCCURS 10 TIMES.
           10 W-HO-COL OCCURS 10 TIMES USAGE COMP-1.
      05 BIAS-O OCCURS 10 TIMES USAGE COMP-1.

    01 NETWORK-VARIABLES.
      05 CURRENT-INPUT OCCURS 784 TIMES USAGE COMP-1.
      05 CURRENT-LABEL PIC 9(1).
      05 HIDDEN-OUT OCCURS 10 TIMES USAGE COMP-1.
      05 OUTPUT-OUT OCCURS 10 TIMES USAGE COMP-1.
    01 NEURAL-NETWORK-TEMP.
        05 TEMP-SUM        USAGE COMP-1.
        05 TEMP-EXP        USAGE COMP-1.
        05 EXP-SUM         USAGE COMP-1.
        05 HINDEX          PIC 9(4).
        05 OINDEX          PIC 9(4).
        05 IINDEX          PIC 9(4).
        05 Z-H OCCURS 10 TIMES USAGE COMP-1.
        05 Z-O OCCURS 10 TIMES USAGE COMP-1.
        05 DELTA-O OCCURS 10 TIMES USAGE COMP-1.
        05 DELTA-H OCCURS 10 TIMES USAGE COMP-1.
        05 ONE-HOT OCCURS 10 TIMES USAGE COMP-1.
        05 LEARNING-RATE USAGE COMP-1 VALUE 0.001.
        
        05 CORRECT-COUNT   PIC 9(5) VALUE 0.
        05 TOTAL-TESTED    PIC 9(5) VALUE 0.
        05 ACCURACY        PIC 9(3)V9(2) VALUE 0.
        05 MAX-PROB        USAGE COMP-1.
        05 PREDICTED-LABEL PIC 9(2).

        05 MAX-Z           USAGE COMP-1.  *> For softmax stability
        05 QUOTIENT          PIC 9(5).       *> For modulus division
        05 REMAINDER-VALUE   PIC 9(5).       *> For modulus remainder
PROCEDURE DIVISION.
MAIN-ROUTINE.
    PERFORM INITIALIZATION-ROUTINE
    DISPLAY "Loading MNIST data..."
    PERFORM PROCESS-TRAIN-RECORDS UNTIL TRAIN-END-OF-FILE
    PERFORM PROCESS-TEST-RECORDS UNTIL TEST-END-OF-FILE
    DISPLAY "Initialized neural network."
    PERFORM INITIALIZE-NETWORK
    DISPLAY "Starting training..."
    PERFORM VARYING EPOCH FROM 1 BY 1 UNTIL EPOCH > 5
        DISPLAY "Epoch " EPOCH " of 5"
        PERFORM VARYING CURRENT-IMAGE FROM 1 BY 1 UNTIL CURRENT-IMAGE > TRAIN-COUNT
             IF FUNCTION MOD(CURRENT-IMAGE, 100) = 0
               DISPLAY "Training image " CURRENT-IMAGE " of " TRAIN-COUNT
             END-IF
            PERFORM VARYING IINDEX FROM 1 BY 1 UNTIL IINDEX > 784
                MOVE PIX(CURRENT-IMAGE, IINDEX) TO CURRENT-INPUT(IINDEX)
            END-PERFORM
            MOVE IMAGE-LABEL(CURRENT-IMAGE) TO CURRENT-LABEL
            PERFORM FORWARD-PASS
            PERFORM BACKPROPAGATION
        END-PERFORM

        PERFORM EVALUATE-ACCURACY
    END-PERFORM
    DISPLAY "Training complete."
    DISPLAY "Evaluating accuracy on test set..."
    PERFORM EVALUATE-ACCURACY
    PERFORM TERMINATION-ROUTINE
    STOP RUN.

INITIALIZATION-ROUTINE.
    OPEN INPUT TRAIN-FILE
    OPEN INPUT TEST-FILE

    *> Skip header in train file
    READ TRAIN-FILE INTO TRAIN-RECORD
        AT END MOVE 'Y' TO TRAIN-EOF-FLAG
    END-READ
    IF TRAIN-RECORD(1:5) = "label"
        CONTINUE
    ELSE
        CLOSE TRAIN-FILE
        OPEN INPUT TRAIN-FILE
    END-IF

    *> Skip header in test file
    READ TEST-FILE INTO TEST-RECORD
        AT END MOVE 'Y' TO TEST-EOF-FLAG
    END-READ
    IF TEST-RECORD(1:5) = "label"
        CONTINUE
    ELSE
        CLOSE TEST-FILE
        OPEN INPUT TEST-FILE
    END-IF.

PROCESS-TRAIN-RECORDS.
    READ TRAIN-FILE INTO TRAIN-RECORD
        AT END MOVE 'Y' TO TRAIN-EOF-FLAG
        NOT AT END
            COMPUTE TRAIN-INDEX = TRAIN-COUNT + 1
            IF TRAIN-INDEX <= 60000
                MOVE TRAIN-RECORD TO INPUT-RECORD
                MOVE "TRAIN" TO DATA-TYPE
                PERFORM PROCESS-MNIST-RECORD
            ELSE
                MOVE 'Y' TO TRAIN-EOF-FLAG
            END-IF
    END-READ.

PROCESS-TEST-RECORDS.
    READ TEST-FILE INTO TEST-RECORD
        AT END MOVE 'Y' TO TEST-EOF-FLAG
        NOT AT END
            COMPUTE TEST-INDEX = TEST-COUNT + 1
            IF TEST-INDEX <= 10000
                MOVE TEST-RECORD TO INPUT-RECORD
                MOVE "TEST" TO DATA-TYPE
                PERFORM PROCESS-MNIST-RECORD
            ELSE
                MOVE 'Y' TO TEST-EOF-FLAG
            END-IF
    END-READ.

FIND-NEXT-FIELD.
    MOVE SPACES TO FIELD-DATA
    MOVE START-PTR TO DELIM-PTR
    PERFORM UNTIL DELIM-PTR > FUNCTION LENGTH(INPUT-RECORD)
       OR INPUT-RECORD(DELIM-PTR:1) = ','
       ADD 1 TO DELIM-PTR
    END-PERFORM
    COMPUTE TEMP-LEN = DELIM-PTR - START-PTR
    IF TEMP-LEN > 0
        MOVE INPUT-RECORD(START-PTR:TEMP-LEN) TO FIELD-DATA
    END-IF
    ADD 1 TO DELIM-PTR
    MOVE DELIM-PTR TO START-PTR.

PROCESS-MNIST-RECORD.
    MOVE 0 TO FIELD-COUNTER
    MOVE 1 TO START-PTR

    *> Lire le label
    PERFORM FIND-NEXT-FIELD
    MOVE FUNCTION NUMVAL(FIELD-DATA) TO THE-LABEL

    *> Stocker le label dans le bon tableau
    IF DATA-TYPE = "TRAIN"
        MOVE THE-LABEL TO IMAGE-LABEL (TRAIN-INDEX)
    ELSE
        MOVE THE-LABEL TO IMAGE-LABEL-TEST (TEST-INDEX)
    END-IF

    *> Lire et ajouter les pixels dans le bon tableau (normalized)
    PERFORM VARYING FIELD-COUNTER FROM 1 BY 1
       UNTIL FIELD-COUNTER > 784 OR START-PTR > FUNCTION LENGTH(INPUT-RECORD)
       PERFORM FIND-NEXT-FIELD
       MOVE FUNCTION NUMVAL(FIELD-DATA) TO PIXEL-VALUE    *> Get raw value (0-255)
       COMPUTE NORMALIZED-PIXEL = PIXEL-VALUE / 255       *> Normalize to 0-1
       IF DATA-TYPE = "TRAIN"
           MOVE NORMALIZED-PIXEL TO PIX (TRAIN-INDEX, FIELD-COUNTER)
       ELSE
           MOVE NORMALIZED-PIXEL TO PIX-TEST (TEST-INDEX, FIELD-COUNTER)
       END-IF
    END-PERFORM

    *> Increment counters
    IF DATA-TYPE = "TRAIN"
        ADD 1 TO TRAIN-COUNT
    ELSE
        ADD 1 TO TEST-COUNT
    END-IF
    COMPUTE RECORD-COUNT = TRAIN-COUNT + TEST-COUNT.


INITIALIZE-NETWORK.
    *> Initialize weights between input and hidden layers randomly
    PERFORM VARYING TRAIN-INDEX FROM 1 BY 1 UNTIL TRAIN-INDEX > 784
        PERFORM VARYING FIELD-COUNTER FROM 1 BY 1 UNTIL FIELD-COUNTER > 10
           COMPUTE W-IH-COL(TRAIN-INDEX, FIELD-COUNTER) = (FUNCTION RANDOM() * 0.0714 - 0.0357)
        END-PERFORM
    END-PERFORM

    *> Initialize weights between hidden and output layers randomly
    PERFORM VARYING TRAIN-INDEX FROM 1 BY 1 UNTIL TRAIN-INDEX > 10
        PERFORM VARYING FIELD-COUNTER FROM 1 BY 1 UNTIL FIELD-COUNTER > 10
           COMPUTE W-HO-COL(TRAIN-INDEX, FIELD-COUNTER) = (FUNCTION RANDOM() * 0.0714 - 0.0357)
        END-PERFORM
    END-PERFORM

    *> Initialize biases to zero
    PERFORM VARYING TRAIN-INDEX FROM 1 BY 1 UNTIL TRAIN-INDEX > 10
        MOVE 0 TO BIAS-H(TRAIN-INDEX)
        MOVE 0 TO BIAS-O(TRAIN-INDEX)
    END-PERFORM.

FORWARD-PASS.
    *> Step 1: Compute hidden layer outputs with ReLU
    PERFORM VARYING HINDEX FROM 1 BY 1 UNTIL HINDEX > 10
        MOVE 0 TO TEMP-SUM
        PERFORM VARYING IINDEX FROM 1 BY 1 UNTIL IINDEX > 784
            COMPUTE TEMP-SUM = TEMP-SUM +
                (CURRENT-INPUT(IINDEX) * W-IH-COL(IINDEX, HINDEX))
        END-PERFORM
        COMPUTE TEMP-SUM = TEMP-SUM + BIAS-H(HINDEX)
        MOVE TEMP-SUM TO Z-H(HINDEX)
        IF TEMP-SUM > 0
            MOVE TEMP-SUM TO HIDDEN-OUT(HINDEX)
        ELSE
            MOVE 0 TO HIDDEN-OUT(HINDEX)
        END-IF
        *> Corrected modulus check for debugging output
        DIVIDE CURRENT-IMAGE BY 100 GIVING QUOTIENT REMAINDER REMAINDER-VALUE
        IF REMAINDER-VALUE = 0
            DISPLAY "HIDDEN-OUT(" HINDEX "): " HIDDEN-OUT(HINDEX)
        END-IF
    END-PERFORM
    *> Step 2: Compute output layer pre-activations
    PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
        MOVE 0 TO TEMP-SUM
        PERFORM VARYING HINDEX FROM 1 BY 1 UNTIL HINDEX > 10
            COMPUTE TEMP-SUM = TEMP-SUM +
                (HIDDEN-OUT(HINDEX) * W-HO-COL(HINDEX, OINDEX))
        END-PERFORM
        COMPUTE TEMP-SUM = TEMP-SUM + BIAS-O(OINDEX)
        MOVE TEMP-SUM TO Z-O(OINDEX)
    END-PERFORM
    *> Step 3: Find MAX-Z from current Z-O values
    MOVE Z-O(1) TO MAX-Z
    PERFORM VARYING OINDEX FROM 2 BY 1 UNTIL OINDEX > 10
        IF Z-O(OINDEX) > MAX-Z
            MOVE Z-O(OINDEX) TO MAX-Z
        END-IF
    END-PERFORM
    *> Step 4: Compute stabilized softmax
    MOVE 0 TO EXP-SUM
    PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
        COMPUTE TEMP-EXP = FUNCTION EXP(Z-O(OINDEX) - MAX-Z)
        MOVE TEMP-EXP TO OUTPUT-OUT(OINDEX)
        ADD TEMP-EXP TO EXP-SUM
        *> Corrected modulus check for debugging output
        DIVIDE CURRENT-IMAGE BY 100 GIVING QUOTIENT REMAINDER REMAINDER-VALUE
        IF REMAINDER-VALUE = 0
            DISPLAY "EXP-SUM for OINDEX " OINDEX ": " EXP-SUM
        END-IF
    END-PERFORM
    *> Step 5: Normalize outputs with safety check
    IF EXP-SUM = 0
        DISPLAY "Warning: EXP-SUM is zero, setting uniform probabilities"
        PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
            COMPUTE OUTPUT-OUT(OINDEX) = 0.1
        END-PERFORM
    ELSE
        PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
            COMPUTE OUTPUT-OUT(OINDEX) = OUTPUT-OUT(OINDEX) / EXP-SUM
        END-PERFORM
    END-IF.
       
BACKPROPAGATION.
    *> Create one-hot vector for the true label
    PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
        IF OINDEX = CURRENT-LABEL + 1
            MOVE 1 TO ONE-HOT(OINDEX)
        ELSE
            MOVE 0 TO ONE-HOT(OINDEX)
        END-IF
    END-PERFORM

    *> Compute output layer gradients
    PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
        COMPUTE DELTA-O(OINDEX) = OUTPUT-OUT(OINDEX) - ONE-HOT(OINDEX)
        *> Clipgradients
        IF DELTA-O(OINDEX) > 1
            MOVE 1 TO DELTA-O(OINDEX)
        END-IF
        IF DELTA-O(OINDEX) < -1
          MOVE -1 TO DELTA-O(OINDEX)
        END-IF
        if FUNCTION MOD(CURRENT-IMAGE, 100) = 0
            DISPLAY "DELTA-O(" OINDEX "): " DELTA-O(OINDEX)  *> Debug
        END-IF
    END-PERFORM

    *> Update output layer weights and biases
    PERFORM VARYING HINDEX FROM 1 BY 1 UNTIL HINDEX > 10
        PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
            COMPUTE W-HO-COL(HINDEX, OINDEX) = W-HO-COL(HINDEX, OINDEX) -
                (LEARNING-RATE * HIDDEN-OUT(HINDEX) * DELTA-O(OINDEX))
        END-PERFORM
    END-PERFORM
    PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
        COMPUTE BIAS-O(OINDEX) = BIAS-O(OINDEX) - (LEARNING-RATE * DELTA-O(OINDEX))
    END-PERFORM

    *> Compute hidden layer gradients
    PERFORM VARYING HINDEX FROM 1 BY 1 UNTIL HINDEX > 10
        MOVE 0 TO TEMP-SUM
        PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
            COMPUTE TEMP-SUM = TEMP-SUM + (W-HO-COL(HINDEX, OINDEX) * DELTA-O(OINDEX))
        END-PERFORM
        IF Z-H(HINDEX) > 0
            MOVE TEMP-SUM TO DELTA-H(HINDEX)
        ELSE
            MOVE 0 TO DELTA-H(HINDEX)
        END-IF
    END-PERFORM

    *> Update hidden layer weights and biases
    PERFORM VARYING IINDEX FROM 1 BY 1 UNTIL IINDEX > 784
        PERFORM VARYING HINDEX FROM 1 BY 1 UNTIL HINDEX > 10
            COMPUTE W-IH-COL(IINDEX, HINDEX) = W-IH-COL(IINDEX, HINDEX) -
                (LEARNING-RATE * CURRENT-INPUT(IINDEX) * DELTA-H(HINDEX))
        END-PERFORM
    END-PERFORM
    PERFORM VARYING HINDEX FROM 1 BY 1 UNTIL HINDEX > 10
        COMPUTE BIAS-H(HINDEX) = BIAS-H(HINDEX) - (LEARNING-RATE * DELTA-H(HINDEX))
    END-PERFORM.

EVALUATE-ACCURACY.
    MOVE 0 TO CORRECT-COUNT
    MOVE 0 TO TOTAL-TESTED
    PERFORM VARYING TEST-INDEX FROM 1 BY 1 UNTIL TEST-INDEX > TEST-COUNT
        *> Load test image into CURRENT-INPUT
        PERFORM VARYING IINDEX FROM 1 BY 1 UNTIL IINDEX > 784
            MOVE PIX-TEST(TEST-INDEX, IINDEX) TO CURRENT-INPUT(IINDEX)
        END-PERFORM
        MOVE IMAGE-LABEL-TEST(TEST-INDEX) TO CURRENT-LABEL
        PERFORM FORWARD-PASS
        *> Find predicted label (index of max probability)
        MOVE 0 TO MAX-PROB
        MOVE 0 TO PREDICTED-LABEL
        PERFORM VARYING OINDEX FROM 1 BY 1 UNTIL OINDEX > 10
            IF OUTPUT-OUT(OINDEX) > MAX-PROB
                MOVE OUTPUT-OUT(OINDEX) TO MAX-PROB
                COMPUTE PREDICTED-LABEL = OINDEX - 1  *> Adjust for 0-9 labels
            END-IF
        END-PERFORM
        *> Check if prediction matches true label
        IF PREDICTED-LABEL = CURRENT-LABEL
            ADD 1 TO CORRECT-COUNT
        END-IF
        ADD 1 TO TOTAL-TESTED
    END-PERFORM
    *> Calculate accuracy as percentage
    COMPUTE ACCURACY = (CORRECT-COUNT * 100.00) / TOTAL-TESTED
    DISPLAY "Accuracy: " ACCURACY "%".

TERMINATION-ROUTINE.
    CLOSE TRAIN-FILE
    CLOSE TEST-FILE.
